import 'dart:convert';
import 'dart:io';

import 'claude.dart';

/// حسابات المستخدمين والفحوصات والاشتراكات، في ملفات JSON داخل [dir] (بدون قاعدة بيانات، يكفي لآلاف المستخدمين).
///
/// - `accounts.json`: لكل حساب الباقة وتاريخ انتهائها والفحوصات المستخدمة.
/// - `settings.json`: عدد الفحوصات المجانية وسقف كل باقة والأسعار، وتتغير من لوحة الأدمن.
/// - `scans/YYYY-MM.jsonl`: سطر لكل فحص ناجح فيه النوع والثقة والوقت والتكلفة بالدولار.
/// - `codes.json`: رموز الهدايا (لفريق مراجعة المتجر أو للتسويق): كم فحص يعطي الرمز وكم حساب يقدر يستخدمه.
///
/// الحساب هو رقم عشوائي يولّده التطبيق أول مرة ويحفظه، وما فيه اسم ولا جوال ولا إيميل.
class AccountStore {
  AccountStore._(this.dir, this._accounts, this.settings, this._codes);

  final String dir;
  final Map<String, Map<String, dynamic>> _accounts;
  final Map<String, dynamic> settings;
  final Map<String, Map<String, dynamic>> _codes;

  static const plans = {'free', 'monthly', 'yearly', 'shop'};
  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');
  static final codePattern = RegExp(r'^[A-Z0-9-]{4,32}$');

  static const defaults = <String, dynamic>{
    'freeScans': 3,
    'monthlyCap': 15,
    'shopCap': 150,
    // false: التطبيقات القديمة اللي ما ترسل رقم حساب تشتغل بدون حد. نخليها true بعد ما ينتشر التحديث.
    'requireAccount': false,
    'priceMonthly': 10,
    'priceYearly': 90,
    'priceShop': 149,
    // الصافي بعد عمولة المتجر 15% وضريبة القيمة المضافة 15%.
    'netShare': 0.74,
    'usdToSar': 3.75,
  };

  /// يرجّع null إذا المجلد غير موجود، فتنطفي الحسابات بهدوء.
  static AccountStore? open(String dir) {
    if (!Directory(dir).existsSync()) return null;
    Map<String, dynamic> read(String name) {
      final f = File('$dir/$name');
      return f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : {};
    }

    Map<String, Map<String, dynamic>> maps(String name) => read(name).map((k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()));
    return AccountStore._(dir, maps('accounts.json'), {...defaults, ...read('settings.json')}, maps('codes.json'));
  }

  int _int(String k) => (settings[k] as num?)?.toInt() ?? (defaults[k] as num).toInt();
  bool get requireAccount => settings['requireAccount'] == true;

  static String _month(DateTime t) => t.toUtc().toIso8601String().substring(0, 7);

  Map<String, dynamic> account(String id, DateTime now) =>
      _accounts.putIfAbsent(id, () => {'created': now.toUtc().toIso8601String(), 'plan': 'free', 'freeUsed': 0, 'bonus': 0});

  Map<String, dynamic>? find(String id) => _accounts[id];

  bool _active(Map<String, dynamic> a, DateTime now) {
    if (a['plan'] == 'free') return false;
    final until = DateTime.tryParse('${a['until']}');
    return until != null && until.isAfter(now);
  }

  /// الفحوصات المتبقية بدون الهدايا: للمشترك من سقف الشهر، ولغيره من الفحوصات المجانية مرة وحدة.
  int _base(Map<String, dynamic> a, DateTime now) {
    if (_active(a, now)) {
      final used = a['month'] == _month(now) ? (a['monthUsed'] as int? ?? 0) : 0;
      return _int(a['plan'] == 'shop' ? 'shopCap' : 'monthlyCap') - used;
    }
    return _int('freeScans') - (a['freeUsed'] as int? ?? 0);
  }

  int remaining(String id, DateTime now) {
    final a = account(id, now);
    final base = _base(a, now);
    return (base > 0 ? base : 0) + (a['bonus'] as int? ?? 0);
  }

  /// يرفض الفحص قبل ما نكلم Claude إذا الحساب موقوف أو خلصت فحوصاته.
  void check(String id, DateTime now) {
    final a = account(id, now);
    if (a['blocked'] == true) throw const FishIdError('blocked', 'هذا الحساب موقوف، تواصل معنا', status: 403);
    if (remaining(id, now) <= 0) {
      throw FishIdError(
        'quota',
        _active(a, now) ? 'خلصت فحوصات هذا الشهر، ترجع مع بداية الشهر الجاي' : 'خلصت فحوصاتك المجانية (${_int('freeScans')}). اشترك عشان تكمل الفحص',
        status: 402,
      );
    }
  }

  /// يحسب فحصًا ناجحًا على الحساب ويكتبه في سجل الشهر.
  Future<void> record(String? id, DateTime now, {required String result, required double usd, required int ms, required int photos}) async {
    if (id != null) {
      final a = account(id, now);
      if (_base(a, now) > 0) {
        if (_active(a, now)) {
          if (a['month'] != _month(now)) a['monthUsed'] = 0;
          a['month'] = _month(now);
          a['monthUsed'] = (a['monthUsed'] as int? ?? 0) + 1;
        } else {
          a['freeUsed'] = (a['freeUsed'] as int? ?? 0) + 1;
        }
      } else {
        a['bonus'] = ((a['bonus'] as int? ?? 0) - 1).clamp(0, 1 << 30);
      }
      a['scans'] = (a['scans'] as int? ?? 0) + 1;
      a['lastScan'] = now.toUtc().toIso8601String();
      await _save();
    }
    String? species;
    int? confidence;
    try {
      final r = jsonDecode(result) as Map<String, dynamic>;
      final c = (r['candidates'] as List?)?.cast<Map>();
      if (c != null && c.isNotEmpty) {
        species = '${c.first['id']}'.padLeft(4, '0');
        confidence = (c.first['confidence'] as num?)?.toInt();
      }
    } on Object {
      // النتيجة نحفظها في السجل بدون النوع إذا ما قدرنا نقرأها.
    }
    final line = jsonEncode({
      'at': now.toUtc().toIso8601String(),
      'user': id,
      'species': ?species,
      'confidence': ?confidence,
      'photos': photos,
      'ms': ms,
      'usd': double.parse(usd.toStringAsFixed(5)),
    });
    Directory('$dir/scans').createSync();
    await File('$dir/scans/${_month(now)}.jsonl').writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  /// تعديل من الأدمن أو من RevenueCat: هدية فحوصات، أو باقة لعدد أيام، أو إيقاف.
  Future<Map<String, dynamic>> update(String id, DateTime now, {int? grant, String? plan, DateTime? until, bool? blocked}) async {
    final a = account(id, now);
    if (grant != null) a['bonus'] = ((a['bonus'] as int? ?? 0) + grant).clamp(0, 100000);
    if (plan != null && plans.contains(plan)) {
      a['plan'] = plan;
      if (plan == 'free') {
        a.remove('until');
      } else if (until != null) {
        a['until'] = until.toUtc().toIso8601String();
      }
    }
    if (blocked != null) a['blocked'] = blocked;
    await _save();
    return view(id, now);
  }

  Map<String, dynamic> view(String id, DateTime now) {
    final a = account(id, now);
    return {'id': id, ...a, 'active': _active(a, now), 'remaining': remaining(id, now)};
  }

  /// آخر الحسابات (الأحدث أولًا)، مع بحث بجزء من الرقم أو بالباقة.
  List<Map<String, dynamic>> users(DateTime now, {String q = '', int limit = 100}) {
    final ids = _accounts.keys.where((id) => q.isEmpty || id.contains(q) || _accounts[id]!['plan'] == q).toList()
      ..sort((a, b) => '${_accounts[b]!['lastScan'] ?? _accounts[b]!['created']}'.compareTo('${_accounts[a]!['lastScan'] ?? _accounts[a]!['created']}'));
    return [for (final id in ids.take(limit)) view(id, now)];
  }

  /// يضيف فحوصات الرمز للحساب، مرة وحدة لكل حساب، ولين يوصل الرمز حده.
  Future<Map<String, dynamic>> redeem(String id, String code, DateTime now) async {
    code = code.trim().toUpperCase();
    final c = codePattern.hasMatch(code) ? _codes[code] : null;
    if (c == null) throw const FishIdError('bad_code', 'الرمز غير صحيح');
    final a = account(id, now);
    final used = (a['codes'] as List?)?.cast<String>() ?? const [];
    if (used.contains(code)) throw const FishIdError('code_used', 'استخدمت هذا الرمز من قبل');
    if ((c['used'] as int? ?? 0) >= (c['max'] as int? ?? 0)) throw const FishIdError('code_full', 'انتهى هذا الرمز');
    c['used'] = (c['used'] as int? ?? 0) + 1;
    a['codes'] = [...used, code];
    a['bonus'] = (a['bonus'] as int? ?? 0) + (c['scans'] as int? ?? 0);
    await _write('codes.json', _codes);
    await _save();
    return view(id, now);
  }

  List<Map<String, dynamic>> codes() => [
    for (final e in _codes.entries) {'code': e.key, ...e.value},
  ];

  /// ينشئ رمزًا أو يعدّله. [max] = 0 يحذفه.
  Future<void> saveCode(String code, {required int scans, required int max}) async {
    code = code.trim().toUpperCase();
    if (!codePattern.hasMatch(code)) throw const FishIdError('bad_request', 'الرمز لازم يكون حروف إنجليزية كبيرة وأرقام، من 4 إلى 32');
    if (max <= 0) {
      _codes.remove(code);
    } else {
      _codes[code] = {...?_codes[code], 'scans': scans.clamp(1, 1000), 'max': max};
    }
    await _write('codes.json', _codes);
  }

  Future<void> saveSettings(Map<String, dynamic> changes) async {
    for (final e in changes.entries) {
      final d = defaults[e.key];
      if (d == null) continue;
      if (d is bool && e.value is bool) settings[e.key] = e.value;
      if (d is num && e.value is num && (e.value as num) >= 0) settings[e.key] = d is int ? (e.value as num).round() : e.value;
    }
    await _write('settings.json', settings);
  }

  /// فحوصات الشهر الحالي (والشهر اللي قبله إذا [months] = 2)، الأحدث أولًا.
  List<Map<String, dynamic>> scans(DateTime now, {int months = 1}) {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < months; i++) {
      final f = File('$dir/scans/${_month(DateTime.utc(now.year, now.month - i))}.jsonl');
      if (!f.existsSync()) continue;
      for (final l in f.readAsLinesSync()) {
        if (l.trim().isNotEmpty) out.add(jsonDecode(l) as Map<String, dynamic>);
      }
    }
    return out.reversed.toList();
  }

  Map<String, dynamic> stats(DateTime now) {
    final today = now.toUtc().toIso8601String().substring(0, 10);
    final week = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
    final month = scans(now);
    final todays = month.where((s) => '${s['at']}'.startsWith(today)).toList();
    double usd(Iterable<Map<String, dynamic>> l) => l.fold(0.0, (t, s) => t + ((s['usd'] as num?) ?? 0));
    final byPlan = {for (final p in plans) p: 0};
    var newWeek = 0, newToday = 0, outOfFree = 0;
    for (final a in _accounts.values) {
      final p = _active(a, now) ? a['plan'] as String : 'free';
      byPlan[p] = byPlan[p]! + 1;
      if ('${a['created']}'.compareTo(week) > 0) newWeek++;
      if ('${a['created']}'.startsWith(today)) newToday++;
      if (p == 'free' && (a['freeUsed'] as int? ?? 0) >= _int('freeScans')) outOfFree++;
    }
    final net = (settings['netShare'] as num).toDouble();
    final sar = (settings['usdToSar'] as num).toDouble();
    // دخل شهري تقديري: الشهري بسعره، والسنوي مقسوم على 12، والمحلات (بوابة دفع، بدون عمولة متجر تقريبًا).
    final mrr =
        byPlan['monthly']! * _int('priceMonthly') * net + byPlan['yearly']! * _int('priceYearly') / 12 * net + byPlan['shop']! * _int('priceShop') * 0.97;
    final costMonth = usd(month) * sar;
    final species = <String, int>{};
    for (final s in month) {
      if (s['species'] case final String sp) species[sp] = (species[sp] ?? 0) + 1;
    }
    return {
      'users': _accounts.length,
      'newToday': newToday,
      'newWeek': newWeek,
      'plans': byPlan,
      'outOfFree': outOfFree,
      'paying': byPlan['monthly']! + byPlan['yearly']! + byPlan['shop']!,
      'scansToday': todays.length,
      'scansMonth': month.length,
      'costTodaySar': usd(todays) * sar,
      'costMonthSar': costMonth,
      'costPerScanSar': month.isEmpty ? 0 : costMonth / month.length,
      'avgSeconds': month.isEmpty ? 0 : month.fold<int>(0, (t, s) => t + ((s['ms'] as num?)?.toInt() ?? 0)) / month.length / 1000,
      'mrrSar': mrr,
      'profitMonthSar': mrr - costMonth,
      'topSpecies': (species.entries.toList()..sort((a, b) => b.value - a.value)).take(10).map((e) => {'id': e.key, 'n': e.value}).toList(),
    };
  }

  Future<void> _save() => _write('accounts.json', _accounts);

  Future<void> _queue = Future.value();

  /// نكتب في ملف مؤقت ثم نبدّله، عشان ما يخرب الملف لو انقطع السيرفر وقت الكتابة. والكتابات بالدور.
  Future<void> _write(String name, Object data) {
    final text = jsonEncode(data);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/$name.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/$name');
    });
  }
}
