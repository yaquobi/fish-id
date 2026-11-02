import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'claude.dart';

/// يجيب عملية دفع من ميسر (GET /v1/payments/{id})، و null إذا تعذّر الاتصال.
typedef PaymentLookup = Future<Map<String, dynamic>?> Function(String id);

/// ينشئ عملية دفع في ميسر (POST /v1/payments)، ونستخدمه للتجديد بالبطاقة المحفوظة.
typedef PaymentCharge = Future<Map<String, dynamic>?> Function(Map<String, dynamic> body);

/// بوابة الدفع ميسر (moyasar.com): مدى، فيزا، ماستركارد، Apple Pay، STC Pay.
/// المفتاح العام [publishableKey] يروح لصفحة الدفع، والسري يبقى في السيرفر داخل [fetch] و [charge].
class Gateway {
  const Gateway({required this.publishableKey, required this.fetch, required this.charge, this.webhookSecret = '', this.methods = const ['creditcard']});

  final String publishableKey;
  final PaymentLookup fetch;
  final PaymentCharge charge;

  /// secret_token اللي نكتبه في إعداد الـ webhook في لوحة ميسر.
  final String webhookSecret;

  /// طرق الدفع في الصفحة: creditcard (مدى والبطاقات)، و applepay و stcpay بعد ما تتفعّل في حساب ميسر.
  final List<String> methods;

  /// مفاتيح التجربة: المبالغ ما تنحسب دخل حقيقي.
  bool get test => publishableKey.startsWith('pk_test');
}

/// المحلات والمطاعم اللي تشترك من hawat.id/shop وتدفع أونلاين.
///
/// كل محل له لوحة برابط خاص فيه مفتاح ([key]، يبدأ بـ s_)، وفيها يربط جوالات موظفينه برقم حساب التطبيق،
/// أو الموظف يكتب رمز المحل (SHOP-XXXXXX) في «عندك رمز؟» على أندرويد. كل الأجهزة تسحب من رصيد واحد بالشهر.
/// الملف `shops.json` في مجلد الحسابات.
class ShopStore {
  ShopStore._(this.dir, this._all);

  final String dir;
  final Map<String, Map<String, dynamic>> _all;

  static final keyPattern = RegExp(r'^s_[0-9a-f]{32}$');
  static final joinPattern = RegExp(r'^SHOP-[A-Z0-9]{6}$');
  static const kinds = {'market', 'shop', 'restaurant', 'hotel', 'other'};
  static const kindNames = {'market': 'سوق سمك', 'shop': 'محل سمك', 'restaurant': 'مطعم', 'hotel': 'فندق أو تموين', 'other': 'أخرى'};

  static ShopStore open(String dir) {
    final f = File('$dir/shops.json');
    final m = f.existsSync()
        ? (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>()))
        : <String, Map<String, dynamic>>{};
    return ShopStore._(dir, m);
  }

  static final _phone = RegExp(r'^(\+?9665|05)[0-9]{8}$');
  static final _email = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,}$');

  static String _hex(int bytes) {
    final rnd = Random.secure();
    return List.generate(bytes, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String _joinCode() {
    // بدون الحروف اللي تتلخبط (O و 0، I و 1).
    const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    while (true) {
      final c = 'SHOP-${List.generate(6, (_) => abc[rnd.nextInt(abc.length)]).join()}';
      if (!_all.values.any((s) => s['join'] == c)) return c;
    }
  }

  /// يسجّل محل جديد (قبل الدفع). يرجّع المحل ومعه مفتاح لوحته.
  Future<Map<String, dynamic>> create(Map b, DateTime now) async {
    String text(String k, int max) {
      final v = '${b[k] ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
      return v.length > max ? v.substring(0, max) : v;
    }

    final name = text('name', 80), city = text('city', 40), email = text('email', 120);
    final phone = text('phone', 20).replaceAll(RegExp(r'[\s-]'), '');
    final cr = text('cr', 20).replaceAll(RegExp(r'\s'), '');
    if (name.length < 2) throw const FishIdError('bad_request', 'اكتب اسم المحل');
    if (city.isEmpty) throw const FishIdError('bad_request', 'اكتب المدينة');
    if (!_phone.hasMatch(phone)) throw const FishIdError('bad_request', 'اكتب جوال سعودي صحيح، مثل 05xxxxxxxx');
    if (email.isNotEmpty && !_email.hasMatch(email)) throw const FishIdError('bad_request', 'الإيميل غير صحيح');
    if (cr.isNotEmpty && !RegExp(r'^[0-9]{10}$').hasMatch(cr)) throw const FishIdError('bad_request', 'رقم السجل التجاري 10 أرقام');
    if (_all.values.where((s) => s['payments'] == null || (s['payments'] as List).isEmpty).length >= 2000) {
      throw const FishIdError('busy', 'التسجيل مزدحم، كلّمنا واتساب', status: 429);
    }
    final id = 'shop_${_hex(5)}';
    final shop = <String, dynamic>{
      'key': 's_${_hex(16)}',
      'name': name,
      'kind': kinds.contains(b['kind']) ? b['kind'] : 'other',
      'city': city,
      'phone': phone,
      'email': email,
      'cr': cr,
      'join': _joinCode(),
      'created': now.toUtc().toIso8601String(),
      'autoRenew': b['autoRenew'] != false,
      'devices': <String>[],
      'payments': <Map<String, dynamic>>[],
    };
    _all[id] = shop;
    await save();
    return {'id': id, ...shop};
  }

  Map<String, dynamic>? byId(String id) => _all[id];

  /// صاحب المفتاح، بمقارنة بوقت ثابت مع كل المفاتيح.
  (String, Map<String, dynamic>)? byKey(String key) {
    if (!keyPattern.hasMatch(key)) return null;
    (String, Map<String, dynamic>)? found;
    for (final e in _all.entries) {
      final k = '${e.value['key']}';
      if (k.length != key.length) continue;
      var d = 0;
      for (var i = 0; i < key.length; i++) {
        d |= k.codeUnitAt(i) ^ key.codeUnitAt(i);
      }
      if (d == 0 && e.value['stopped'] != true) found = (e.key, e.value);
    }
    return found;
  }

  (String, Map<String, dynamic>)? byJoin(String code) {
    code = code.trim().toUpperCase();
    if (!joinPattern.hasMatch(code)) return null;
    for (final e in _all.entries) {
      if (e.value['join'] == code && e.value['stopped'] != true) return (e.key, e.value);
    }
    return null;
  }

  /// المحل اللي فيه هذا الجهاز، إن وجد.
  String? shopOf(String account) {
    for (final e in _all.entries) {
      if ((e.value['devices'] as List).contains(account)) return e.key;
    }
    return null;
  }

  Iterable<MapEntry<String, Map<String, dynamic>>> get entries => _all.entries;

  List<Map<String, dynamic>> list() => [
    for (final e in _all.entries) {'id': e.key, ...e.value},
  ]..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));

  static bool active(Map<String, dynamic> s, DateTime now) {
    final until = DateTime.tryParse('${s['until']}');
    return s['stopped'] != true && until != null && until.isAfter(now);
  }

  static int used(Map<String, dynamic> s, DateTime now) => s['month'] == now.toUtc().toIso8601String().substring(0, 7) ? (s['monthUsed'] as int? ?? 0) : 0;

  static bool hasPayment(Map<String, dynamic> s, String id) => (s['payments'] as List).any((p) => (p as Map)['id'] == id);

  /// يمد الاشتراك شهر من نهايته (أو من الحين إذا كان منتهي) ويسجّل الدفعة. يرجّع تاريخ الانتهاء الجديد.
  Future<DateTime> paid(String id, Map<String, dynamic> payment, DateTime now, {String? token, String? card}) async {
    final s = _all[id]!;
    final current = DateTime.tryParse('${s['until']}');
    final from = current != null && current.isAfter(now) ? current : now.toUtc();
    final until = DateTime.utc(from.year, from.month + 1, from.day, from.hour, from.minute);
    s['until'] = until.toIso8601String();
    s['payments'] = [
      ...(s['payments'] as List),
      {...payment, 'until': s['until']},
    ];
    if (token != null) {
      s['token'] = token;
      s['card'] = card;
    }
    s.remove('renewTries');
    s.remove('renewError');
    s.remove('reminded');
    s.remove('stopped');
    await save();
    return until;
  }

  Future<void> save() => _write('shops.json', _all);

  Future<void> _queue = Future.value();

  Future<void> _write(String name, Object data) {
    final text = jsonEncode(data);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/$name.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/$name');
    });
  }
}
