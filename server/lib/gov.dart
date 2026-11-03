import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'claude.dart';

/// الفئة الرسمية: جهات حكومية (مثل وزارة البيئة والمياه والزراعة) تشترك بعقد، ومفتشينها يفحصون بلا حد.
///
/// - الجهة لها لوحة على `/api/gov?k=` بمفتاح خاص ([agency] key يبدأ بـ g_)، فيها الزيارات والمخالفات والمفتشين.
/// - كل مفتش له رمز `GOV-XXXXXX` يكتبه في التطبيق («دخول المفتشين»)، فيرتبط جهازه بالجهة (حد جهازين).
/// - الزيارة التفتيشية: المحل وما هو مكتوب على لوحته، ونتيجة الفحص، وقرار المفتش وملاحظته والموقع، ورقم مرجعي INS-YYYY-NNNNN.
///   الذكاء الاصطناعي استرشادي، والقرار للمفتش.
///
/// الملفات في مجلد الحسابات: `gov.json` (الجهات والمفتشين)، و `gov-visits.jsonl` (سطر لكل زيارة)، و `gov-photos/` (صور الزيارات).
class GovStore {
  GovStore._(this.dir, this._agencies, this._inspectors, this._visits, this._seq);

  final String dir;
  final Map<String, Map<String, dynamic>> _agencies;
  final Map<String, Map<String, dynamic>> _inspectors;
  final List<Map<String, dynamic>> _visits;
  int _seq;

  static final keyPattern = RegExp(r'^g_[0-9a-f]{32}$');
  static final codePattern = RegExp(r'^GOV-[A-Z0-9]{6}$');
  static final refPattern = RegExp(r'^INS-[0-9]{4}-[0-9]{5}$');

  /// أقصى عدد أجهزة لكل مفتش (جواله وجهاز احتياط).
  static const maxDevices = 2;

  /// أنواع المخالفات اللي يختارها المفتش.
  static const violationTypes = {
    'name': ('تسمية مضللة للصنف', 'Misleading species name'),
    'fresh': ('سمك غير طازج', 'Not fresh'),
    'price': ('السعر غير معلن أو مخالف', 'Price not shown or wrong'),
    'hygiene': ('النظافة والتبريد', 'Hygiene and chilling'),
    'other': ('أخرى', 'Other'),
  };
  static const decisions = {'ok', 'violation', 'followup'};

  static GovStore open(String dir) {
    final f = File('$dir/gov.json');
    final m = f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : <String, dynamic>{};
    Map<String, Map<String, dynamic>> maps(Object? v) => v is Map ? v.map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())) : {};
    final visits = <Map<String, dynamic>>[];
    final vf = File('$dir/gov-visits.jsonl');
    if (vf.existsSync()) {
      for (final line in vf.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          visits.add((jsonDecode(line) as Map).cast<String, dynamic>());
        } on FormatException {
          // سطر ناقص (انقطع الحفظ) نتجاهله.
        }
      }
    }
    return GovStore._(dir, maps(m['agencies']), maps(m['inspectors']), visits, (m['seq'] as num?)?.toInt() ?? visits.length);
  }

  static String _hex(int bytes) {
    final rnd = Random.secure();
    return List.generate(bytes, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String _code() {
    // بدون الحروف اللي تتلخبط (O و 0، I و 1).
    const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    while (true) {
      final c = 'GOV-${List.generate(6, (_) => abc[rnd.nextInt(abc.length)]).join()}';
      if (!_inspectors.values.any((i) => i['code'] == c)) return c;
    }
  }

  static String _text(Object? v, int max) {
    final s = '${v ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
    return s.length > max ? s.substring(0, max) : s;
  }

  static final _phone = RegExp(r'^(\+?9665|05)[0-9]{8}$');

  // ---------- الجهات ----------

  /// جهة جديدة من لوحة الأدمن: الاسم وعدد الرخص (المفتشين) وتاريخ نهاية العقد.
  Future<Map<String, dynamic>> addAgency(Map b, DateTime now) async {
    final name = _text(b['name'], 120);
    if (name.length < 3) throw const FishIdError('bad_request', 'اكتب اسم الجهة');
    final seats = (b['seats'] as num?)?.toInt() ?? 5;
    if (seats < 1 || seats > 10000) throw const FishIdError('bad_request', 'عدد الرخص غير صحيح');
    final until = DateTime.tryParse('${b['until'] ?? ''}');
    if (until == null) throw const FishIdError('bad_request', 'اكتب تاريخ نهاية العقد');
    final id = 'ag_${_hex(5)}';
    _agencies[id] = {
      'name': name,
      'key': 'g_${_hex(16)}',
      'seats': seats,
      'until': DateTime.utc(until.year, until.month, until.day, 23, 59).toIso8601String(),
      'contact': _text(b['contact'], 120),
      'pilot': b['pilot'] == true,
      'created': now.toUtc().toIso8601String(),
    };
    await save();
    return {'id': id, ..._agencies[id]!};
  }

  /// تعديل جهة من الأدمن: تمديد العقد، عدد الرخص، إيقاف، مفتاح لوحة جديد.
  Future<Map<String, dynamic>> updateAgency(String id, Map b) async {
    final a = _agencies[id];
    if (a == null) throw const FishIdError('not_found', 'الجهة غير موجودة', status: 404);
    if (b['seats'] is num) {
      final s = (b['seats'] as num).toInt();
      if (s < 1 || s > 10000) throw const FishIdError('bad_request', 'عدد الرخص غير صحيح');
      a['seats'] = s;
    }
    if (b['until'] != null) {
      final u = DateTime.tryParse('${b['until']}');
      if (u == null) throw const FishIdError('bad_request', 'التاريخ غير صحيح');
      a['until'] = DateTime.utc(u.year, u.month, u.day, 23, 59).toIso8601String();
    }
    if (b['stopped'] is bool) a['stopped'] = b['stopped'];
    if (b['pilot'] is bool) a['pilot'] = b['pilot'];
    if (b['newKey'] == true) a['key'] = 'g_${_hex(16)}';
    await save();
    return {'id': id, ...a};
  }

  Map<String, dynamic>? agency(String id) => _agencies[id];

  static bool active(Map<String, dynamic>? a, DateTime now) {
    if (a == null || a['stopped'] == true) return false;
    final until = DateTime.tryParse('${a['until']}');
    return until != null && until.isAfter(now);
  }

  /// صاحب مفتاح اللوحة، بمقارنة بوقت ثابت.
  (String, Map<String, dynamic>)? byKey(String key) {
    if (!keyPattern.hasMatch(key)) return null;
    (String, Map<String, dynamic>)? found;
    for (final e in _agencies.entries) {
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

  // ---------- المفتشين ----------

  Iterable<MapEntry<String, Map<String, dynamic>>> _of(String agency) => _inspectors.entries.where((e) => e.value['agency'] == agency);

  int _seatsUsed(String agency) => _of(agency).where((e) => e.value['stopped'] != true).length;

  /// مفتش جديد في جهة (من الأدمن أو من لوحة الجهة). يرجّع المفتش ومعه رمزه.
  Future<Map<String, dynamic>> addInspector(String agency, Map b, DateTime now) async {
    final a = _agencies[agency];
    if (a == null) throw const FishIdError('not_found', 'الجهة غير موجودة', status: 404);
    final name = _text(b['name'], 80);
    final branch = _text(b['branch'], 80);
    final phone = _text(b['phone'], 20).replaceAll(RegExp(r'[\s-]'), '');
    if (name.length < 3) throw const FishIdError('bad_request', 'اكتب اسم المفتش');
    if (phone.isNotEmpty && !_phone.hasMatch(phone)) throw const FishIdError('bad_request', 'اكتب جوال سعودي صحيح، مثل 05xxxxxxxx');
    if (_seatsUsed(agency) >= ((a['seats'] as num?)?.toInt() ?? 0)) {
      throw const FishIdError('seats', 'وصلتم لعدد الرخص في العقد. أوقفوا مفتش أو كلمونا لزيادة الرخص', status: 409);
    }
    final id = 'in_${_hex(5)}';
    _inspectors[id] = {
      'agency': agency,
      'name': name,
      'branch': branch,
      'phone': phone,
      'code': _code(),
      'devices': <String>[],
      'created': now.toUtc().toIso8601String(),
    };
    await save();
    return {'id': id, ..._inspectors[id]!};
  }

  /// إيقاف أو تفعيل مفتش، أو فك أجهزته (رمز جديد يوقف القديم).
  Future<Map<String, dynamic>> updateInspector(String id, Map b, {String? agency}) async {
    final i = _inspectors[id];
    if (i == null || (agency != null && i['agency'] != agency)) throw const FishIdError('not_found', 'المفتش غير موجود', status: 404);
    if (b['stopped'] is bool) {
      if (b['stopped'] == false && i['stopped'] == true) {
        final a = _agencies[i['agency']];
        if (_seatsUsed('${i['agency']}') >= ((a?['seats'] as num?)?.toInt() ?? 0)) {
          throw const FishIdError('seats', 'وصلتم لعدد الرخص في العقد', status: 409);
        }
      }
      i['stopped'] = b['stopped'];
    }
    if (b['newCode'] == true) {
      i['code'] = _code();
      i['devices'] = <String>[];
    }
    await save();
    return {'id': id, ...i};
  }

  /// المفتش من رمزه.
  (String, Map<String, dynamic>)? byCode(String code) {
    code = code.trim().toUpperCase();
    if (!codePattern.hasMatch(code)) return null;
    for (final e in _inspectors.entries) {
      if (e.value['code'] == code) return (e.key, e.value);
    }
    return null;
  }

  /// المفتش المربوط بهذا الحساب، إن وجد.
  (String, Map<String, dynamic>)? inspectorOf(String account) {
    for (final e in _inspectors.entries) {
      if ((e.value['devices'] as List).contains(account)) return (e.key, e.value);
    }
    return null;
  }

  /// يربط جهاز المفتش برمزه. يرمي خطأ إذا الرمز موقوف أو العقد منتهي أو الرمز على جهازين.
  Future<Map<String, dynamic>> join(String code, String account, DateTime now) async {
    final found = byCode(code);
    if (found == null) throw const FishIdError('bad_code', 'رمز المفتش غير صحيح');
    final (id, i) = found;
    final a = _agencies[i['agency']];
    if (i['stopped'] == true) throw const FishIdError('gov_stopped', 'هذا الرمز موقوف، كلم مشرفك', status: 403);
    if (!active(a, now)) throw const FishIdError('gov_expired', 'اشتراك الجهة منتهي أو موقوف', status: 403);
    // الجهاز مربوط بمفتش ثاني: نفكه منه أول.
    for (final e in _inspectors.entries) {
      if (e.key != id) (e.value['devices'] as List).remove(account);
    }
    final devices = (i['devices'] as List).cast<String>();
    if (!devices.contains(account)) {
      if (devices.length >= maxDevices) throw const FishIdError('gov_devices', 'هذا الرمز مستخدم على جهازين. اطلب من مشرفك رمز جديد', status: 409);
      i['devices'] = [...devices, account];
    }
    i['lastSeen'] = now.toUtc().toIso8601String();
    await save();
    return profile(account, now)!;
  }

  /// خروج المفتش من الوضع الرسمي على هذا الجهاز.
  Future<bool> leave(String account) async {
    final found = inspectorOf(account);
    if (found == null) return false;
    (found.$2['devices'] as List).remove(account);
    await save();
    return true;
  }

  /// بيانات المفتش للتطبيق، أو null إذا الجهاز مو مربوط.
  Map<String, dynamic>? profile(String account, DateTime now) {
    final found = inspectorOf(account);
    if (found == null) return null;
    final (id, i) = found;
    final a = _agencies[i['agency']];
    final month = now.toUtc().toIso8601String().substring(0, 7);
    final today = now.toUtc().toIso8601String().substring(0, 10);
    final mine = _visits.where((v) => v['inspector'] == id);
    return {
      'id': id,
      'name': i['name'],
      'branch': i['branch'],
      'code': i['code'],
      'agency': a?['name'] ?? '',
      'until': a?['until'],
      'active': i['stopped'] != true && active(a, now),
      'month': mine.where((v) => '${v['at']}'.startsWith(month)).length,
      'today': mine.where((v) => '${v['at']}'.startsWith(today)).length,
    };
  }

  /// الحساب يفحص بلا حد: مفتش مفعّل في جهة عقدها ساري.
  bool unlimited(String account, DateTime now) {
    final found = inspectorOf(account);
    if (found == null) return false;
    return found.$2['stopped'] != true && active(_agencies[found.$2['agency']], now);
  }

  // ---------- الزيارات ----------

  /// يحفظ زيارة تفتيشية من جهاز المفتش، مع صورها (حد 3). يرجّع الزيارة برقمها المرجعي.
  Future<Map<String, dynamic>> addVisit(String account, Map b, List<Photo> photos, DateTime now) async {
    final found = inspectorOf(account);
    if (found == null) throw const FishIdError('gov_none', 'سجّل دخول المفتش أول', status: 403);
    final (iid, i) = found;
    if (!unlimited(account, now)) throw const FishIdError('gov_expired', 'اشتراك الجهة منتهي أو الرمز موقوف', status: 403);
    final today = now.toUtc().toIso8601String().substring(0, 10);
    if (_visits.where((v) => v['inspector'] == iid && '${v['at']}'.startsWith(today)).length >= 300) {
      throw const FishIdError('busy', 'وصلت حد الزيارات لليوم', status: 429);
    }
    final shop = _text(b['shop'], 80);
    final market = _text(b['market'], 80);
    if (shop.isEmpty) throw const FishIdError('bad_request', 'اكتب اسم المحل');
    if (market.isEmpty) throw const FishIdError('bad_request', 'اكتب اسم السوق');
    final decision = decisions.contains(b['decision']) ? b['decision'] as String : throw const FishIdError('bad_request', 'اختر نتيجة الزيارة');
    final violations = <String>{
      for (final v in (b['violations'] as List? ?? const []))
        if (violationTypes.containsKey(v)) '$v',
    }.toList();
    if (decision == 'violation' && violations.isEmpty) throw const FishIdError('bad_request', 'اختر نوع المخالفة');
    num? n(Object? v, num min, num max) => v is num && v >= min && v <= max ? v : null;
    final r = b['result'] is Map ? b['result'] as Map : const {};
    final year = now.toUtc().year;
    _seq++;
    final ref = 'INS-$year-${'$_seq'.padLeft(5, '0')}';
    final visit = <String, dynamic>{
      'ref': ref,
      'agency': i['agency'],
      'inspector': iid,
      'inspectorName': i['name'],
      'branch': i['branch'],
      'at': now.toUtc().toIso8601String(),
      'market': market,
      'city': _text(b['city'], 40),
      'shop': shop,
      'labelName': _text(b['labelName'], 60),
      'labelPrice': n(b['labelPrice'], 0, 100000),
      'species': _text(r['species'], 8),
      'speciesName': _text(r['name'], 60),
      'sci': _text(r['sci'], 80),
      'confidence': n(r['confidence'], 0, 100)?.toInt(),
      'freshness': n(r['freshness'], 0, 100)?.toInt(),
      'grade': _text(r['grade'], 20),
      'match': b['match'] is bool ? b['match'] : null,
      'decision': decision,
      'violations': decision == 'ok' ? <String>[] : violations,
      'note': _text(b['note'], 500),
      'lat': n(b['lat'], -90, 90),
      'lng': n(b['lng'], -180, 180),
      'photos': photos.length,
    }..removeWhere((k, v) => v == null);
    if (photos.isNotEmpty) {
      final d = Directory('$dir/gov-photos')..createSync(recursive: true);
      for (var k = 0; k < photos.length; k++) {
        await File('${d.path}/$ref-$k.${photos[k].mediaType == 'image/png' ? 'png' : 'jpg'}').writeAsBytes(photos[k].bytes, flush: true);
      }
    }
    _visits.add(visit);
    i['lastSeen'] = visit['at'];
    await File('$dir/gov-visits.jsonl').writeAsString('${jsonEncode(visit)}\n', mode: FileMode.append, flush: true);
    await save();
    return visit;
  }

  /// آخر زيارات المفتش (للتطبيق).
  List<Map<String, dynamic>> visitsOf(String account, {int limit = 50}) {
    final found = inspectorOf(account);
    if (found == null) return const [];
    return _visits.reversed.where((v) => v['inspector'] == found.$1).take(limit).toList();
  }

  Map<String, dynamic>? visit(String ref) {
    for (final v in _visits.reversed) {
      if (v['ref'] == ref) return v;
    }
    return null;
  }

  /// صورة زيارة، إذا الزيارة تتبع [agency].
  File? photo(String agency, String ref, int n) {
    if (!refPattern.hasMatch(ref) || n < 0 || n > 2) return null;
    final v = visit(ref);
    if (v == null || v['agency'] != agency) return null;
    for (final ext in const ['jpg', 'png']) {
      final f = File('$dir/gov-photos/$ref-$n.$ext');
      if (f.existsSync()) return f;
    }
    return null;
  }

  // ---------- لوحة الجهة ----------

  /// ملخص الجهة لشهر ([month] بصيغة YYYY-MM): الأرقام، والأسواق، والأيام، وآخر الزيارات، والمفتشين.
  Map<String, dynamic> dashboard(String agency, String month, DateTime now) {
    final a = _agencies[agency]!;
    final all = _visits.where((v) => v['agency'] == agency).toList();
    final inMonth = all.where((v) => '${v['at']}'.startsWith(month)).toList();
    bool bad(Map v) => v['decision'] == 'violation';
    final byType = {for (final k in violationTypes.keys) k: 0};
    final markets = <String, Map<String, dynamic>>{};
    final inspectors = <String, Map<String, int>>{};
    final days = <String, List<int>>{};
    final mismatch = <String, int>{};
    for (final v in inMonth) {
      for (final t in (v['violations'] as List? ?? const [])) {
        byType[t] = (byType[t] ?? 0) + 1;
      }
      final mk = '${v['market']}|${v['city'] ?? ''}';
      final m = markets.putIfAbsent(mk, () => {'market': v['market'], 'city': v['city'] ?? '', 'visits': 0, 'violations': 0});
      m['visits'] = (m['visits'] as int) + 1;
      if (bad(v)) m['violations'] = (m['violations'] as int) + 1;
      final ins = inspectors.putIfAbsent('${v['inspector']}', () => {'visits': 0, 'violations': 0});
      ins['visits'] = ins['visits']! + 1;
      if (bad(v)) ins['violations'] = ins['violations']! + 1;
      final d = days.putIfAbsent('${v['at']}'.substring(0, 10), () => [0, 0]);
      d[0]++;
      if (bad(v)) d[1]++;
      if (v['match'] == false && '${v['labelName']}'.isNotEmpty) {
        final k = '${v['labelName']} ← ${v['speciesName']}';
        mismatch[k] = (mismatch[k] ?? 0) + 1;
      }
    }
    final y = int.parse(month.substring(0, 4)), mo = int.parse(month.substring(5, 7));
    final last = DateTime.utc(y, mo + 1, 0).day;
    final topMismatch = mismatch.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'agency': {'name': a['name'], 'until': a['until'], 'seats': a['seats'], 'active': active(a, now), 'pilot': a['pilot'] == true},
      'month': month,
      'visits': inMonth.length,
      'violations': inMonth.where(bad).length,
      'followup': inMonth.where((v) => v['decision'] == 'followup').length,
      'mismatch': inMonth.where((v) => v['match'] == false).length,
      'byType': byType,
      'topMismatch': [
        for (final e in topMismatch.take(5)) {'label': e.key, 'count': e.value},
      ],
      'markets': markets.values.toList()..sort((a, b) => (b['visits'] as int).compareTo(a['visits'] as int)),
      'days': [
        for (var d = 1; d <= last; d++)
          () {
            final k = '$month-${'$d'.padLeft(2, '0')}';
            return {'day': k, 'visits': days[k]?[0] ?? 0, 'violations': days[k]?[1] ?? 0};
          }(),
      ],
      'visitsList': inMonth.reversed.take(300).toList(),
      'inspectors': [
        for (final e in _of(agency))
          {
            'id': e.key,
            'name': e.value['name'],
            'branch': e.value['branch'],
            'phone': e.value['phone'],
            'code': e.value['code'],
            'devices': (e.value['devices'] as List).length,
            'stopped': e.value['stopped'] == true,
            'lastSeen': e.value['lastSeen'],
            'visits': inspectors[e.key]?['visits'] ?? 0,
            'violations': inspectors[e.key]?['violations'] ?? 0,
          },
      ]..sort((a, b) => (b['visits'] as int).compareTo(a['visits'] as int)),
      'seatsUsed': _seatsUsed(agency),
      'months': {for (final v in all) '${v['at']}'.substring(0, 7)}.toList()..sort((a, b) => b.compareTo(a)),
    };
  }

  /// كل الجهات للوحة الأدمن، مع عدد المفتشين والزيارات هالشهر.
  List<Map<String, dynamic>> list(DateTime now) {
    final month = now.toUtc().toIso8601String().substring(0, 7);
    return [
      for (final e in _agencies.entries)
        {
          'id': e.key,
          ...e.value,
          'active': active(e.value, now),
          'seatsUsed': _seatsUsed(e.key),
          'visitsMonth': _visits.where((v) => v['agency'] == e.key && '${v['at']}'.startsWith(month)).length,
          'violationsMonth': _visits.where((v) => v['agency'] == e.key && '${v['at']}'.startsWith(month) && v['decision'] == 'violation').length,
          'inspectors': [
            for (final i in _of(e.key))
              {
                'id': i.key,
                'name': i.value['name'],
                'branch': i.value['branch'],
                'phone': i.value['phone'],
                'code': i.value['code'],
                'devices': (i.value['devices'] as List).length,
                'stopped': i.value['stopped'] == true,
                'lastSeen': i.value['lastSeen'],
                'visitsMonth': _visits.where((v) => v['inspector'] == i.key && '${v['at']}'.startsWith(month)).length,
              },
          ],
        },
    ]..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));
  }

  Future<void> save() => _write('gov.json', {'agencies': _agencies, 'inspectors': _inspectors, 'seq': _seq});

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
