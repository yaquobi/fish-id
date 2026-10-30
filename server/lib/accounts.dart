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
    'shopCap': 300,
    // false: التطبيقات القديمة اللي ما ترسل رقم حساب تشتغل بدون حد. نخليها true بعد ما ينتشر التحديث.
    'requireAccount': false,
    'priceMonthly': 25,
    'priceYearly': 199,
    'priceShop': 350,
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

  /// كل الحسابات، للتقارير.
  Iterable<Map<String, dynamic>> get all => _accounts.values;

  /// عدد المشتركين الحاليين في كل باقة مدفوعة.
  Map<String, int> paying(DateTime now) {
    final out = {'monthly': 0, 'yearly': 0, 'shop': 0};
    for (final a in _accounts.values) {
      if (_active(a, now)) out[a['plan'] as String] = (out[a['plan']] ?? 0) + 1;
    }
    return out;
  }

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
  Future<Map<String, dynamic>> update(String id, DateTime now, {int? grant, String? plan, DateTime? until, bool? blocked, String? source, String? by}) async {
    final a = account(id, now);
    // سجل تعديلات الأدمن (آخر 30) يظهر في تفاصيل الحساب.
    if (by != null) {
      a['log'] = [
        ...((a['log'] as List?) ?? const []).skip(((a['log'] as List?)?.length ?? 0) >= 30 ? 1 : 0),
        {'at': now.toUtc().toIso8601String(), 'by': by, 'grant': ?grant, 'plan': ?plan, 'until': ?until?.toUtc().toIso8601String(), 'blocked': ?blocked},
      ];
    }
    if (grant != null) a['bonus'] = ((a['bonus'] as int? ?? 0) + grant).clamp(0, 100000);
    if (plan != null && plans.contains(plan)) {
      a['plan'] = plan;
      // من وين جت الباقة: store من RevenueCat، وبدونها من الأدمن.
      if (source != null) {
        a['source'] = source;
      } else {
        a.remove('source');
      }
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
    final out = {'id': id, ...a, 'active': _active(a, now), 'remaining': remaining(id, now), 'cap': _cap(a, now), 'status': _status(a, now), 'from': _from(a)};
    out.remove('log');
    return out;
  }

  /// سقف الفحوصات اللي يُقاس عليه الرصيد: سقف الشهر للمشترك، والمجانية لغيره.
  int _cap(Map<String, dynamic> a, DateTime now) => _active(a, now) ? _int(a['plan'] == 'shop' ? 'shopCap' : 'monthlyCap') : _int('freeScans');

  /// حالة الحساب في لوحة الأدمن: blocked موقوف، soon ينتهي خلال 7 أيام، active مشترك، empty مجاني خلص رصيده، free مجاني.
  String _status(Map<String, dynamic> a, DateTime now) {
    if (a['blocked'] == true) return 'blocked';
    if (_active(a, now)) return DateTime.parse('${a['until']}').difference(now).inDays < 7 ? 'soon' : 'active';
    return _base(a, now) > 0 || (a['bonus'] as int? ?? 0) > 0 ? 'free' : 'empty';
  }

  /// من وين جت الباقة أو الرصيد: store المتجر، manual من الأدمن، code رمز هدية، وفاضي للمجاني العادي.
  String _from(Map<String, dynamic> a) {
    if (a['plan'] != 'free') return a['source'] == 'store' ? 'store' : 'manual';
    return (a['codes'] as List?)?.isNotEmpty == true ? 'code' : '';
  }

  static const views = {'all', 'paid', 'free', 'soon', 'blocked'};

  bool _inView(String view, Map<String, dynamic> a, DateTime now) {
    final st = _status(a, now);
    return switch (view) {
      'paid' => st == 'active' || st == 'soon',
      'free' => st == 'free' || st == 'empty',
      'soon' => st == 'soon',
      'blocked' => st == 'blocked',
      _ => true,
    };
  }

  /// صفحة من الحسابات (الأحدث نشاطًا أولًا) مع الفلاتر، وعدد كل عرض للأرقام والتبويبات.
  /// [q] جزء من رقم الحساب أو اسم الباقة، [activity] 24 أو 168 ساعة أو none (ما فحص أبد).
  Map<String, dynamic> users(DateTime now, {String q = '', String tab = 'all', String plan = '', String from = '', String activity = '', int page = 1, int size = 50}) {
    bool match(String id) {
      final a = _accounts[id]!;
      if (q.isNotEmpty && !id.contains(q) && a['plan'] != q) return false;
      if (plan.isNotEmpty && a['plan'] != plan) return false;
      if (from.isNotEmpty && _from(a) != from) return false;
      if (activity.isNotEmpty) {
        final last = DateTime.tryParse('${a['lastScan']}');
        if (activity == 'none' ? last != null : (last == null || now.difference(last).inHours > (int.tryParse(activity) ?? 0))) return false;
      }
      return true;
    }

    final found = _accounts.keys.where(match).toList();
    final counts = {for (final v in views) v: found.where((id) => _inView(v, _accounts[id]!, now)).length};
    final ids = found.where((id) => _inView(views.contains(tab) ? tab : 'all', _accounts[id]!, now)).toList()
      ..sort((a, b) => '${_accounts[b]!['lastScan'] ?? _accounts[b]!['created']}'.compareTo('${_accounts[a]!['lastScan'] ?? _accounts[a]!['created']}'));
    page = page < 1 ? 1 : page;
    size = size.clamp(10, 200);
    return {
      'total': ids.length,
      'page': page,
      'size': size,
      'counts': counts,
      'newWeek': _accounts.values.where((a) => (DateTime.tryParse('${a['created']}') ?? DateTime(2000)).isAfter(now.subtract(const Duration(days: 7)))).length,
      'items': [for (final id in ids.skip((page - 1) * size).take(size)) view(id, now)],
    };
  }

  /// تفاصيل حساب للدرج الجانبي: بياناته وسجل تعديلات الأدمن وآخر فحوصاته (آخر 3 شهور).
  Map<String, dynamic>? detail(String id, DateTime now) {
    final a = _accounts[id];
    if (a == null) return null;
    return {
      ...view(id, now),
      'log': [...((a['log'] as List?) ?? const [])].reversed.toList(),
      'recent': scans(now, months: 3).where((s) => s['user'] == id).take(20).toList(),
    };
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
  List<Map<String, dynamic>> scans(DateTime now, {int months = 1}) => [
    for (var i = months - 1; i >= 0; i--) ...monthScans(_month(DateTime.utc(now.year, now.month - i))),
  ].reversed.toList();

  /// فحوصات شهر واحد ([month] بصيغة YYYY-MM) بترتيبها.
  List<Map<String, dynamic>> monthScans(String month) {
    final f = File('$dir/scans/$month.jsonl');
    if (!f.existsSync()) return [];
    return [
      for (final l in f.readAsLinesSync())
        if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
    ];
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
      'daily': _daily(now, sar),
    };
  }

  /// عدد الفحوصات وتكلفتها لكل يوم من آخر 30 يوم، للرسم في الرئيسية.
  List<Map<String, dynamic>> _daily(DateTime now, double sar) {
    final days = {
      for (var i = 29; i >= 0; i--) now.toUtc().subtract(Duration(days: i)).toIso8601String().substring(0, 10): <String, num>{'n': 0, 'sar': 0.0},
    };
    for (final s in scans(now, months: 2)) {
      final d = days['${s['at']}'.substring(0, 10)];
      if (d == null) continue;
      d['n'] = d['n']! + 1;
      d['sar'] = d['sar']! + ((s['usd'] as num?) ?? 0) * sar;
    }
    return [for (final e in days.entries) {'day': e.key, ...e.value}];
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
