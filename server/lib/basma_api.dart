import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'basma.dart';
import 'claude.dart';

/// عملاء «بصمة API» اللي يشترون النموذج للشركات والجهات (hawat.id/basma).
/// كل عميل له مفتاح سري `bsk_...` يطلع مرة وحدة عند الإنشاء، ونحفظ بصمته (sha256) بس.
/// الملف `basma_clients.json` في مجلد الحسابات. العدّاد شهري بتوقيت السعودية.
class BasmaClients {
  BasmaClients._(this.dir, this._all);

  final String dir;
  final Map<String, Map<String, dynamic>> _all;

  static final keyPattern = RegExp(r'^bsk_[0-9a-f]{40}$');
  static final idPattern = RegExp(r'^bc_[0-9a-f]{12}$');

  /// الباقات بنفس أسعار الصفحة (ريال، بدون ضريبة).
  /// [included] الطلبات المشمولة بالشهر، و [overage] سعر الطلب الزائد. بدون سعر زائد يوقف العميل عند الحد.
  /// التجريبية 50 طلب للمدة كاملة (شهر).
  static const plans = <String, Map<String, Object?>>{
    'trial': {'name': 'تجريبية', 'included': 50, 'overage': null, 'price': 0, 'days': 30},
    'developer': {'name': 'مطوّر', 'included': 5000, 'overage': 0.40, 'price': 1499},
    'business': {'name': 'أعمال', 'included': 50000, 'overage': 0.20, 'price': 7500},
    'gov': {'name': 'جهة حكومية', 'included': 0, 'overage': null, 'price': 0},
  };

  static const vat = 0.15;

  static BasmaClients open(String dir) {
    final f = File('$dir/basma_clients.json');
    final m = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())) : <String, Map<String, dynamic>>{};
    return BasmaClients._(dir, m);
  }

  /// الشهر بتوقيت السعودية، مثل 2026-11.
  static String month(DateTime now) => now.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 7);

  static String _hash(String key) => sha256.convert(utf8.encode(key)).toString();

  static String _hex(int bytes) {
    final rnd = Random.secure();
    return List.generate(bytes, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// العميل الفعّال صاحب المفتاح (مع رقمه في 'id')، أو null.
  Map<String, dynamic>? find(String key) {
    if (!keyPattern.hasMatch(key)) return null;
    final h = _hash(key);
    for (final e in _all.entries) {
      if (e.value['hash'] == h) return e.value['active'] == false ? null : {'id': e.key, ...e.value};
    }
    return null;
  }

  /// كم طلب مشمول وسعر الزائد والسعر الشهري، مع تعديلات الأدمن للعميل (عقود الجهات).
  static ({int included, double? overage, num price}) terms(Map<String, dynamic> c) {
    final p = plans[c['plan']] ?? plans['trial']!;
    return (
      included: (c['included'] as num?)?.toInt() ?? p['included'] as int,
      overage: c.containsKey('overage') ? (c['overage'] as num?)?.toDouble() : p['overage'] as double?,
      price: c['price'] as num? ?? p['price'] as num,
    );
  }

  /// المستخدم في الحد الحالي: التجريبية كل المدة، والباقي الشهر الحالي.
  static int used(Map<String, dynamic> c, DateTime now) => c['plan'] == 'trial' ? (c['total'] as int? ?? 0) : ((c['usage'] as Map?)?[month(now)] as int? ?? 0);

  /// ملخص الشهر للعميل: المستخدم والزائد والمبلغ المستحق بدون الضريبة ومعها.
  static Map<String, dynamic> bill(Map<String, dynamic> c, String month) {
    // ما نحاسب على شهر قبل ما يصير عميل.
    final created = DateTime.tryParse('${c['created'] ?? ''}');
    if (created != null && month.compareTo(BasmaClients.month(created)) < 0) {
      return {'month': month, 'requests': 0, 'included': 0, 'extra': 0, 'price': 0, 'overage': null, 'amount': 0, 'vat': 0, 'total': 0, 'invoiced': false};
    }
    final t = terms(c);
    final n = (c['usage'] as Map?)?[month] as int? ?? 0;
    final extra = t.overage == null || t.included == 0 ? 0 : max(0, n - t.included);
    final amount = ((t.price + extra * (t.overage ?? 0)) * 100).round() / 100;
    return {
      'month': month,
      'requests': n,
      'included': t.included,
      'extra': extra,
      'price': t.price,
      'overage': t.overage,
      'amount': amount,
      'vat': (amount * vat * 100).round() / 100,
      'total': (amount * (1 + vat) * 100).round() / 100,
      'invoiced': ((c['invoiced'] as List?) ?? const []).contains(month),
    };
  }

  /// يتأكد إن العميل يقدر يطلب الحين، ويرمي خطأ واضح للمطوّر إذا لا.
  void check(Map<String, dynamic> c, DateTime now) {
    final until = DateTime.tryParse('${c['until'] ?? ''}');
    if (until != null && now.isAfter(until)) {
      throw const FishIdError('expired', 'This key has expired. Contact info@hawat.id to renew. انتهت مدة المفتاح.', status: 402);
    }
    final t = terms(c);
    if (t.overage == null && t.included > 0 && used(c, now) >= t.included) {
      throw const FishIdError('quota', 'Request quota reached for this plan. انتهى رصيد الطلبات في باقتك.', status: 402);
    }
  }

  /// يحسب طلب ناجح للعميل.
  Future<void> count(String id, DateTime now) async {
    final c = _all[id];
    if (c == null) return;
    final m = month(now);
    final usage = (c['usage'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    usage[m] = (usage[m] as int? ?? 0) + 1;
    c['usage'] = usage;
    c['total'] = (c['total'] as int? ?? 0) + 1;
    c['last'] = now.toUtc().toIso8601String();
    await _save();
  }

  /// للوحة الأدمن: كل العملاء بدون البصمة، مع فاتورة هذا الشهر واللي قبله.
  List<Map<String, dynamic>> list(DateTime now) {
    final m = month(now);
    final prev = month(DateTime.utc(int.parse(m.substring(0, 4)), int.parse(m.substring(5)), 1).subtract(const Duration(days: 1)));
    return [
      for (final e in _all.entries)
        {'id': e.key, ...Map.of(e.value)..remove('hash'), 'planName': plans[e.value['plan']]?['name'], 'used': used(e.value, now), 'bill': bill(e.value, m), 'lastBill': bill(e.value, prev)},
    ]..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));
  }

  static String _text(Object? v, int max) {
    final s = '${v ?? ''}'.trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  /// عميل جديد، ويرجّع المفتاح السري مرة وحدة.
  Future<Map<String, dynamic>> add(Map b, DateTime now) async {
    final name = _text(b['name'], 80);
    final plan = '${b['plan'] ?? 'trial'}';
    if (name.isEmpty) throw const FishIdError('bad_request', 'اكتب اسم العميل');
    if (!plans.containsKey(plan)) throw const FishIdError('bad_request', 'الباقة غير معروفة');
    final id = 'bc_${_hex(6)}';
    final key = 'bsk_${_hex(20)}';
    final days = plans[plan]!['days'] as int?;
    _all[id] = {
      'name': name,
      'contact': _text(b['contact'], 120),
      'country': _text(b['country'], 40),
      'plan': plan,
      'hash': _hash(key),
      'prefix': key.substring(0, 10),
      'created': now.toUtc().toIso8601String(),
      'until': days == null ? null : now.toUtc().add(Duration(days: days)).toIso8601String(),
      'active': true,
      'usage': <String, dynamic>{},
      'total': 0,
      'last': null,
    };
    _applyTerms(_all[id]!, b);
    await _save();
    return {'id': id, 'key': key};
  }

  void _applyTerms(Map<String, dynamic> c, Map b) {
    if (b['included'] is num) c['included'] = (b['included'] as num).toInt().clamp(0, 100000000);
    if (b['price'] is num) c['price'] = (b['price'] as num).clamp(0, 100000000);
    if (b.containsKey('overage') && (b['overage'] == null || b['overage'] is num)) c['overage'] = b['overage'];
  }

  /// تعديل من الأدمن: الباقة، الإيقاف، التمديد، شروط خاصة، أو تسجيل إن فاتورة شهر انسجلت بالمحاسبة.
  Future<Map<String, dynamic>> update(String id, Map b, DateTime now) async {
    final c = _all[id];
    if (c == null) throw const FishIdError('not_found', 'العميل غير موجود', status: 404);
    if (b['plan'] is String) {
      if (!plans.containsKey(b['plan'])) throw const FishIdError('bad_request', 'الباقة غير معروفة');
      c['plan'] = b['plan'];
      // الترقية من التجريبية تشيل تاريخ الانتهاء والشروط القديمة.
      final days = plans[c['plan']]!['days'] as int?;
      c['until'] = days == null ? null : now.toUtc().add(Duration(days: days)).toIso8601String();
      c.remove('included');
      c.remove('price');
      c.remove('overage');
    }
    if (b['active'] is bool) c['active'] = b['active'];
    if (b['extendDays'] is int) {
      final base = DateTime.tryParse('${c['until'] ?? ''}') ?? now.toUtc();
      c['until'] = (base.isBefore(now) ? now.toUtc() : base).add(Duration(days: (b['extendDays'] as int).clamp(1, 3650))).toIso8601String();
    }
    if (b['until'] == null && b.containsKey('until')) c['until'] = null;
    if (b['invoiced'] is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(b['invoiced'] as String)) {
      c['invoiced'] = {...((c['invoiced'] as List?) ?? const []), b['invoiced']}.toList();
    }
    if (b.containsKey('contact')) c['contact'] = _text(b['contact'], 120);
    _applyTerms(c, b);
    await _save();
    return {'id': id, ...Map.of(c)..remove('hash')};
  }

  /// مفتاح جديد لنفس العميل، والقديم يوقف فورًا.
  Future<Map<String, dynamic>> rotate(String id) async {
    final c = _all[id];
    if (c == null) throw const FishIdError('not_found', 'العميل غير موجود', status: 404);
    final key = 'bsk_${_hex(20)}';
    c['hash'] = _hash(key);
    c['prefix'] = key.substring(0, 10);
    await _save();
    return {'id': id, 'key': key};
  }

  Future<void> remove(String id) async {
    _all.remove(id);
    await _save();
  }

  Future<void> _queue = Future.value();

  Future<void> _save() {
    final text = jsonEncode(_all);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/basma_clients.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/basma_clients.json');
    });
  }
}

/// واجهة «بصمة» للعملاء: hawat.id/api/basma/v1/...
///
/// POST basma/v1/identify بمفتاح العميل في `Authorization: Bearer bsk_...`، والجسم صورة (image/jpeg أو png أو webp)
/// أو JSON {"image": BASE64, "mediaType": "image/jpeg"}. اختياري `?top=1..5`.
/// يرجّع أقرب الأنواع من 448 نوعًا في الموسوعة بالاسم العلمي والإنجليزي والمحلي (البحر الأحمر والخليج).
/// GET basma/v1/usage يرجّع الباقة والمستخدم والمتبقي، و GET basma/v1/species قائمة الأنواع (ما تنحسب).
class BasmaApi {
  BasmaApi(this.clients, this.rank, this.species, {this.perMinute = 60, this.notify});

  final BasmaClients clients;
  final BasmaRank rank;

  /// رقم النوع (4 أرقام) → {id, scientific, english, red_sea, gulf, family}.
  final Map<String, Map<String, dynamic>> species;
  final int perMinute;
  final void Function(String text)? notify;

  static const model = 'basma-0.1';
  static const maxBytes = 5 * 1024 * 1024;
  static const types = {'image/jpeg', 'image/png', 'image/webp'};

  final _minute = <String, (int, int)>{};

  /// يبني [species] من ملف الموسوعة. الأسماك تتقدّم على الربيان لأن أرقامهم الأخيرة تتكرر.
  static Map<String, Map<String, dynamic>> speciesFrom(Map<String, dynamic> data) {
    final out = <String, Map<String, dynamic>>{};
    String first(Object? s) => '${s ?? ''}'.split('|').first.trim();
    final list = (data['species'] as List).cast<Map>().toList()..sort((a, b) => ('${a['id']}'.startsWith('HWT-FISH-') ? 0 : 1).compareTo('${b['id']}'.startsWith('HWT-FISH-') ? 0 : 1));
    for (final s in list) {
      final id = '${s['id']}'.split('-').last;
      out.putIfAbsent(
        id,
        () => {'id': s['id'], 'scientific': '${s['sci'] ?? ''}'.trim(), 'english': first(s['en']), 'red_sea': first(s['red']), 'gulf': first(s['gulf']), 'family': '${s['fam'] ?? ''}'.trim()},
      );
    }
    return out;
  }

  Future<Response> handle(Request req, String sub, DateTime now) async {
    try {
      if (req.method == 'GET' && sub == 'species') {
        _client(req, now);
        return _json(200, {'model': model, 'count': species.length, 'species': species.values.toList()});
      }
      final c = _client(req, now);
      if (req.method == 'GET' && sub == 'usage') return _json(200, _usage(c, now));
      if (req.method == 'POST' && sub == 'identify') {
        clients.check(c, now);
        final photo = await _photo(req);
        final top = int.tryParse(req.url.queryParameters['top'] ?? '')?.clamp(1, 5) ?? 5;
        final Map<String, dynamic> r;
        try {
          r = await rank(photo);
        } on Object catch (e) {
          stderr.writeln('basma api: $e');
          throw const FishIdError('unavailable', 'Basma is temporarily unavailable, please retry. الخدمة متوقفة مؤقتًا.', status: 503);
        }
        await clients.count(c['id'] as String, now);
        final after = clients.find(_key(req)) ?? c;
        _milestone(after, now);
        return _json(200, {
          'model': model,
          'results': [
            for (final t in (r['top'] as List).cast<Map>().take(top)) {...?species['${t['id']}'.padLeft(4, '0')], 'score': t['score']},
          ],
          'ms': r['ms'],
          'usage': _usage(after, now),
        });
      }
      throw const FishIdError('not_found', 'Unknown endpoint. See https://hawat.id/basma/', status: 404);
    } on FishIdError catch (e) {
      return _json(e.status, {
        'error': {'code': e.code, 'message': e.message},
      });
    }
  }

  static String _key(Request req) {
    final auth = req.headers['authorization'] ?? '';
    return auth.startsWith('Bearer ') ? auth.substring(7).trim() : (req.headers['x-api-key'] ?? '').trim();
  }

  Map<String, dynamic> _client(Request req, DateTime now) {
    final key = _key(req);
    final c = clients.find(key);
    if (c == null) throw const FishIdError('unauthorized', 'Missing or invalid API key. المفتاح غير صحيح.', status: 401);
    final m = now.millisecondsSinceEpoch ~/ 60000;
    final (at, n) = _minute[c['id']] ?? (m, 0);
    final count = at == m ? n + 1 : 1;
    _minute[c['id'] as String] = (m, count);
    if (count > perMinute) throw FishIdError('rate_limit', 'Too many requests, limit is $perMinute per minute. طلبات كثيرة.', status: 429);
    return c;
  }

  Map<String, dynamic> _usage(Map<String, dynamic> c, DateTime now) {
    final t = BasmaClients.terms(c);
    final used = BasmaClients.used(c, now);
    return {
      'plan': c['plan'],
      'period': c['plan'] == 'trial' ? 'trial' : BasmaClients.month(now),
      'used': used,
      'included': t.included == 0 ? null : t.included,
      'remaining': t.included == 0 ? null : max(0, t.included - used),
      'overage_sar': t.overage,
      'expires': c['until'],
    };
  }

  /// تنبيه للمالك لما العميل يوصل 80% أو يخلص المشمول (مرة وحدة لكل حد بالشهر).
  void _milestone(Map<String, dynamic> c, DateTime now) {
    final t = BasmaClients.terms(c);
    if (notify == null || t.included == 0) return;
    final used = BasmaClients.used(c, now);
    if (used == (t.included * 0.8).ceil() || used == t.included) {
      final full = used == t.included;
      notify!(
        '🔑 بصمة API: ${c['name']} ${full ? 'خلّص' : 'استخدم 80% من'} طلبات باقته (${BasmaClients.plans[c['plan']]?['name']}): $used من ${t.included}'
        '${full && t.overage == null ? '\nتوقف لين نرقيه أو نجدد.' : ''}',
      );
    }
  }

  static Future<Photo> _photo(Request req) async {
    final type = (req.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
    final len = req.contentLength;
    if (len != null && len > maxBytes * 1.4) throw const FishIdError('too_large', 'Image is larger than 5 MB.', status: 413);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      bytes.add(chunk);
      if (bytes.length > maxBytes * 1.4) throw const FishIdError('too_large', 'Image is larger than 5 MB.', status: 413);
    }
    final body = bytes.takeBytes();
    if (types.contains(type)) {
      if (body.isEmpty || body.length > maxBytes) throw const FishIdError('bad_image', 'Send one JPEG, PNG or WebP image up to 5 MB.');
      return Photo(body, type);
    }
    if (type == 'application/json') {
      try {
        final j = jsonDecode(utf8.decode(body)) as Map;
        final mt = '${j['mediaType'] ?? j['media_type'] ?? 'image/jpeg'}';
        final img = base64.decode('${j['image']}'.replaceFirst(RegExp(r'^data:[^,]*,'), ''));
        if (types.contains(mt) && img.isNotEmpty && img.length <= maxBytes) return Photo(img, mt);
      } on Object {
        // تحت
      }
    }
    throw const FishIdError('bad_image', 'Send one JPEG, PNG or WebP image up to 5 MB, as the body or as JSON {"image": base64}.');
  }

  static const _cors = {'access-control-allow-origin': '*', 'access-control-allow-methods': 'POST, GET, OPTIONS', 'access-control-allow-headers': 'content-type, authorization, x-api-key'};

  static Response _json(int status, Object? body) => Response(status, body: jsonEncode(body), headers: {..._cors, 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});
}
