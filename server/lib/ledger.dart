import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'accounts.dart';
import 'ads.dart';
import 'claude.dart';

/// المحاسبة: الدخل والمصاريف والصافي لكل شهر، بالريال. الملفات في نفس مجلد الحسابات:
///
/// - `sales/YYYY-MM.jsonl`: عمليات المتجر من أحداث RevenueCat (اشتراك، تجديد، استرجاع) بالمبلغ وضريبته وعمولة المتجر.
/// - `ledger.json`: قيود يدخلها الأدمن، دخل أو مصروف، مرة وحدة أو يتكرر كل شهر أو كل سنة (مثل الخادم والدومين).
///
/// وتكلفة Claude تنحسب لحالها من سجل الفحوصات، ورسوم RevenueCat (1% بعد أول 2,500 دولار بالشهر) من المبيعات.
class Ledger {
  Ledger._(this.accounts, this._entries, this._alerts);

  final AccountStore accounts;
  final List<Map<String, dynamic>> _entries;

  /// `alerts.json`: رصيد Claude اللي سجله الأدمن ({usd, at})، وآخر مرة رفض فيها Claude الطلبات لكل سبب.
  final Map<String, dynamic> _alerts;

  String get dir => accounts.dir;

  /// صرف الإعلانات الفعلي من البريف اليومي، ينحسب مصروف تلقائي لكل منصة.
  AdStore? ads;

  static const kinds = {'income', 'expense'};
  static const repeats = {'once', 'monthly', 'yearly'};
  static final monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');
  static final datePattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$');

  /// RevenueCat مجاني لين يوصل دخل الشهر 2,500 دولار، وبعدها ياخذ 1% من كامل الدخل.
  static const rcFreeUsd = 2500;
  static const rcShare = 0.01;

  static Ledger open(AccountStore accounts) {
    final f = File('${accounts.dir}/ledger.json');
    final list = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as List).map((e) => (e as Map).cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];
    final a = File('${accounts.dir}/alerts.json');
    return Ledger._(accounts, list, a.existsSync() ? (jsonDecode(a.readAsStringSync()) as Map).cast<String, dynamic>() : {});
  }

  double get _sar => (accounts.settings['usdToSar'] as num).toDouble();

  static String month(DateTime t) => t.toUtc().toIso8601String().substring(0, 7);

  /// يضيف قيدًا بعد التأكد من كل حقل، ويرجّعه.
  Future<Map<String, dynamic>> add(Map<String, dynamic> b, DateTime now) async {
    String text(String k, int max) => '${b[k] ?? ''}'.trim().substring(0, min('${b[k] ?? ''}'.trim().length, max));
    final amount = b['amount'];
    final date = '${b['date'] ?? ''}';
    if (!kinds.contains(b['kind']) || amount is! num || amount <= 0 || amount > 10000000 || !datePattern.hasMatch(date)) {
      throw const FishIdError('bad_request', 'تأكد من النوع والمبلغ والتاريخ');
    }
    final label = text('label', 80);
    if (label.isEmpty) throw const FishIdError('bad_request', 'اكتب وصف القيد');
    final e = {
      'id': '${now.microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}',
      'kind': b['kind'],
      'provider': text('provider', 40),
      'label': label,
      'amount': amount,
      'currency': b['currency'] == 'USD' ? 'USD' : 'SAR',
      'date': date,
      'repeat': repeats.contains(b['repeat']) ? b['repeat'] : 'once',
      'note': text('note', 200),
      'created': now.toUtc().toIso8601String(),
    };
    _entries.add(e);
    await _save();
    return e;
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e['id'] == id);
    await _save();
  }

  /// يوقف القيد المتكرر بعد [last] (يبقى محسوب فيه وفي اللي قبله).
  Future<void> stop(String id, String last) async {
    for (final e in _entries.where((e) => e['id'] == id)) {
      e['end'] = last;
    }
    await _save();
  }

  List<Map<String, dynamic>> entries() => [..._entries]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));

  bool _occurs(Map<String, dynamic> e, String m) {
    final start = '${e['date']}'.substring(0, 7);
    if (m.compareTo(start) < 0) return false;
    if (e['end'] is String && m.compareTo(e['end'] as String) > 0) return false;
    return switch (e['repeat']) {
      'monthly' => true,
      'yearly' => m.substring(5) == start.substring(5),
      _ => m == start,
    };
  }

  double _entrySar(Map<String, dynamic> e) => (e['amount'] as num).toDouble() * (e['currency'] == 'USD' ? _sar : 1);

  /// يسجّل عملية من حدث RevenueCat. [confirmed]: RevenueCat أكد إن المشترك عنده هالمنتج.
  /// المبالغ السالبة (استرجاع) نقبلها بس إذا سجلنا قبلها بيعة لنفس الحساب والمنتج، عشان ما يقدر أحد ينقّص الدخل بحدث مزوّر.
  /// يرجّع true إذا انحفظت.
  Future<bool> recordSale(Map event, {required String user, required bool confirmed, required DateTime now}) async {
    final id = '${event['id'] ?? ''}';
    final price = event['price'];
    if (id.isEmpty || id.length > 100 || price is! num || price == 0) return false;
    final product = '${event['product_id'] ?? ''}';
    final ms = event['event_timestamp_ms'] ?? event['purchased_at_ms'];
    final at = ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : now.toUtc();
    final recent = [for (var i = 0; i < 13; i++) ..._sales(month(DateTime.utc(at.year, at.month - i)))];
    if (recent.any((s) => s['id'] == id)) return false;
    if (price > 0 && !confirmed) return false;
    if (price < 0 && !recent.any((s) => s['user'] == user && s['product'] == product && (s['grossSar'] as num) > 0)) return false;

    final currency = '${event['currency'] ?? ''}';
    final local = event['price_in_purchased_currency'];
    final gross = currency == 'SAR' && local is num ? local.toDouble() : price.toDouble() * _sar;
    final double tax, fee;
    if (event['tax_percentage'] is num && event['commission_percentage'] is num) {
      tax = gross * (event['tax_percentage'] as num);
      fee = gross * (event['commission_percentage'] as num);
    } else {
      // بدون نسب من RevenueCat: ضريبة القيمة المضافة 15% داخل السعر، وعمولة المتجر 15% من الباقي.
      tax = gross - gross / 1.15;
      fee = (gross - tax) * 0.15;
    }
    double r(double v) => double.parse(v.toStringAsFixed(2));
    final line = jsonEncode({
      'id': id,
      'at': at.toIso8601String(),
      'type': '${event['type'] ?? ''}',
      'user': user,
      'product': product,
      'store': '${event['store'] ?? ''}',
      'sandbox': event['environment'] == 'SANDBOX',
      'currency': currency,
      'usd': price,
      'grossSar': r(gross),
      'taxSar': r(tax),
      'feeSar': r(fee),
      'netSar': r(gross - tax - fee),
    });
    Directory('$dir/sales').createSync();
    await File('$dir/sales/${month(at)}.jsonl').writeAsString('$line\n', mode: FileMode.append, flush: true);
    return true;
  }

  List<Map<String, dynamic>> _sales(String m) {
    final f = File('$dir/sales/$m.jsonl');
    if (!f.existsSync()) return [];
    return [
      for (final l in f.readAsLinesSync())
        if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
    ];
  }

  /// كشف شهر [m]: كل سطر دخل ومصروف، والمجاميع.
  Map<String, dynamic> statement(String m) {
    double r(num v) => double.parse(v.toStringAsFixed(2));
    final all = _sales(m);
    final sales = all.where((s) => s['sandbox'] != true).toList();
    final income = <Map<String, dynamic>>[];
    final byProduct = <String, Map<String, dynamic>>{};
    for (final s in sales) {
      final p = byProduct.putIfAbsent(
        '${s['product']}',
        () => {'store': s['store'], 'n': 0, 'refunds': 0, 'grossSar': 0.0, 'taxSar': 0.0, 'feeSar': 0.0, 'netSar': 0.0},
      );
      if ((s['grossSar'] as num) < 0) {
        p['refunds'] = (p['refunds'] as int) + 1;
      } else {
        p['n'] = (p['n'] as int) + 1;
      }
      for (final k in const ['grossSar', 'taxSar', 'feeSar', 'netSar']) {
        p[k] = (p[k] as double) + (s[k] as num);
      }
    }
    for (final e in byProduct.entries) {
      income.add({
        'auto': true,
        'provider': e.value['store'] == 'APP_STORE' ? 'App Store' : 'Google Play',
        'label': e.key.isEmpty ? 'اشتراكات المتجر' : e.key,
        'n': e.value['n'],
        'refunds': e.value['refunds'],
        'grossSar': r(e.value['grossSar'] as double),
        'taxSar': r(e.value['taxSar'] as double),
        'feeSar': r(e.value['feeSar'] as double),
        'sar': r(e.value['netSar'] as double),
      });
    }
    final expenses = <Map<String, dynamic>>[];
    final scans = accounts.monthScans(m);
    final claude = scans.fold<double>(0, (t, s) => t + ((s['usd'] as num?) ?? 0)) * _sar;
    if (scans.isNotEmpty) {
      expenses.add({'auto': true, 'provider': 'Anthropic (Claude)', 'label': 'فحوصات التطبيق', 'n': scans.length, 'sar': r(claude)});
    }
    for (final e in (ads?.monthSpend(m) ?? const <String, double>{}).entries) {
      if (e.value > 0) {
        expenses.add({'auto': true, 'ads': e.key, 'provider': 'إعلانات ${AdStore.names[e.key] ?? e.key}', 'label': 'صرف الإعلانات الفعلي', 'sar': e.value});
      }
    }
    final grossUsd = sales.fold<double>(0, (t, s) => t + (s['usd'] as num));
    if (grossUsd > rcFreeUsd) {
      expenses.add({'auto': true, 'provider': 'RevenueCat', 'label': 'رسوم 1% من دخل المتجر', 'sar': r(grossUsd * rcShare * _sar)});
    }
    for (final e in _entries.where((e) => _occurs(e, m))) {
      (e['kind'] == 'income' ? income : expenses).add({
        'id': e['id'],
        'provider': e['provider'],
        'label': e['label'],
        'repeat': e['repeat'],
        'note': e['note'],
        'original': e['currency'] == 'USD' ? '${e['amount']} USD' : null,
        'sar': r(_entrySar(e)),
      });
    }
    double sum(List<Map<String, dynamic>> l, [String k = 'sar']) => l.fold(0.0, (t, x) => t + ((x[k] as num?) ?? 0));
    final inSar = sum(income), outSar = sum(expenses);
    final providers = <String, double>{};
    for (final e in expenses) {
      final p = '${e['provider']}'.isEmpty ? 'أخرى' : '${e['provider']}';
      providers[p] = (providers[p] ?? 0) + (e['sar'] as num);
    }
    return {
      'month': m,
      'income': income,
      'expenses': expenses,
      'grossSar': r(sum(income.where((x) => x['auto'] == true).toList(), 'grossSar') + sum(income.where((x) => x['auto'] != true).toList())),
      'storeTaxSar': r(sum(income, 'taxSar')),
      'storeFeeSar': r(sum(income, 'feeSar')),
      'incomeSar': r(inSar),
      'expensesSar': r(outSar),
      'netSar': r(inSar - outSar),
      'margin': inSar > 0 ? r((inSar - outSar) / inSar * 100) : null,
      'paidSales': sales.where((s) => (s['grossSar'] as num) > 0).length,
      'sandboxSales': all.length - sales.length,
      'scans': scans.length,
      'providers': [
        for (final e in providers.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {'provider': e.key, 'sar': r(e.value)},
      ],
    };
  }

  /// الدخل والمصاريف والصافي لآخر [n] شهور لين [m]، الأقدم أولًا.
  List<Map<String, dynamic>> history(String m, {int n = 12}) {
    final y = int.parse(m.substring(0, 4)), mo = int.parse(m.substring(5));
    return [
      for (var i = n - 1; i >= 0; i--)
        if (statement(month(DateTime.utc(y, mo - i))) case final s)
          {'month': s['month'], 'incomeSar': s['incomeSar'], 'expensesSar': s['expensesSar'], 'netSar': s['netSar']},
    ];
  }

  /// يسجّل إن Claude رفض الطلبات ([code] = claude_credit أو claude_account).
  Future<void> raise(String code, DateTime now) async {
    _alerts[code] = now.toUtc().toIso8601String();
    await _write('alerts.json', _alerts);
  }

  /// يسجّل رصيد Claude الحالي بالدولار (بعد الشحن أو من صفحة الفوترة). 0 يلغي المتابعة.
  Future<void> setBalance(num usd, DateTime now) async {
    if (usd <= 0) {
      _alerts.remove('balance');
    } else {
      _alerts['balance'] = {'usd': usd, 'at': now.toUtc().toIso8601String()};
    }
    await _write('alerts.json', _alerts);
  }

  /// أقرب موعد (من اليوم) لقيد متكرر أو مرة وحدة، أو null إذا خلص.
  String? _nextDue(Map<String, dynamic> e, DateTime now) {
    final today = now.toUtc().toIso8601String().substring(0, 10);
    final p = '${e['date']}'.split('-').map(int.parse).toList();
    if (e['repeat'] == 'once') return '${e['date']}'.compareTo(today) >= 0 ? '${e['date']}' : null;
    final t = now.toUtc();
    for (var i = 0; i < 25; i++) {
      final d = e['repeat'] == 'yearly' ? DateTime.utc(t.year + i, p[1], min(p[2], 28)) : DateTime.utc(t.year, t.month + i, min(p[2], 28));
      final ds = d.toIso8601String().substring(0, 10);
      if (ds.compareTo(today) < 0 || ds.compareTo('${e['date']}') < 0) continue;
      if (e['end'] is String && ds.substring(0, 7).compareTo(e['end'] as String) > 0) return null;
      return ds;
    }
    return null;
  }

  /// التنبيهات الحالية، الأخطر أولًا. كل تنبيه {level: red|amber|info، code، ...تفاصيل}، والنص يكتبه المتصفح بلغته.
  Map<String, dynamic> alerts(DateTime now) {
    double r(num v) => double.parse(v.toStringAsFixed(2));
    final out = <Map<String, dynamic>>[];
    final thisMonth = accounts.monthScans(month(now));
    final lastScan = thisMonth.isEmpty ? '' : '${thisMonth.last['at']}';
    for (final code in const ['claude_credit', 'claude_account']) {
      // التنبيه يبقى لين ينجح فحص بعده.
      if (_alerts[code] is String && (_alerts[code] as String).compareTo(lastScan) > 0) out.add({'level': 'red', 'code': code, 'at': _alerts[code]});
    }
    Map<String, dynamic>? balance;
    if (_alerts['balance'] case {'usd': final num usd, 'at': final String at}) {
      final since = DateTime.parse(at);
      final scans = [
        for (var d = DateTime.utc(since.year, since.month); !d.isAfter(now); d = DateTime.utc(d.year, d.month + 1)) ...accounts.monthScans(month(d)),
      ];
      final spent = scans.where((s) => '${s['at']}'.compareTo(at) > 0).fold<double>(0, (t, s) => t + ((s['usd'] as num?) ?? 0));
      final weekAgo = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
      final perDay = scans.where((s) => '${s['at']}'.compareTo(weekAgo) > 0).fold<double>(0, (t, s) => t + ((s['usd'] as num?) ?? 0)) / 7;
      final left = usd - spent;
      final days = perDay > 0 ? (left / perDay).floor() : null;
      balance = {'usd': usd, 'at': at, 'spentUsd': r(spent), 'leftUsd': r(left), 'perDayUsd': r(perDay), 'daysLeft': days};
      if (left <= 0) {
        out.add({'level': 'red', 'code': 'balance_out', ...balance});
      } else if (left < usd * 0.2 || (days != null && days < 7)) {
        out.add({'level': 'amber', 'code': 'balance_low', ...balance});
      }
    } else {
      out.add({'level': 'info', 'code': 'balance_unset'});
    }
    final soon = now.add(const Duration(days: 7)).toUtc().toIso8601String().substring(0, 10);
    final upcoming = <Map<String, dynamic>>[];
    for (final e in _entries.where((e) => e['kind'] == 'expense')) {
      final due = _nextDue(e, now);
      if (due == null) continue;
      upcoming.add({'due': due, 'label': e['label'], 'provider': e['provider'], 'sar': r(_entrySar(e)), 'repeat': e['repeat']});
      if (due.compareTo(soon) <= 0) {
        out.add({'level': 'amber', 'code': 'bill_due', 'due': due, 'label': e['label'], 'provider': e['provider'], 'sar': r(_entrySar(e))});
      }
    }
    upcoming.sort((a, b) => '${a['due']}'.compareTo('${b['due']}'));
    return {'alerts': out, 'balance': balance, 'upcoming': upcoming.take(10).toList()};
  }

  Map<String, dynamic> report(String m) => {...statement(m), 'history': history(m), 'entries': entries()};

  Future<void> _queue = Future.value();

  Future<void> _save() => _write('ledger.json', _entries);

  Future<void> _write(String name, Object data) {
    final text = jsonEncode(data);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/$name.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/$name');
    });
  }
}

/// ملخص فترة (يوم أو شهر أو سنة) للمستثمر أو للتقارير: المستخدمين والنمو والفحوصات والاشتراكات والفلوس،
/// مع المقارنة بالفترة اللي قبلها ورسم داخل الفترة.
extension Reports on Ledger {
  static final dayPattern = Ledger.datePattern;
  static final yearPattern = RegExp(r'^20\d\d$');

  /// يتأكد من [key] حسب [period] (day: YYYY-MM-DD، month: YYYY-MM، year: YYYY).
  static bool valid(String period, String key) => switch (period) {
    'day' => dayPattern.hasMatch(key),
    'month' => Ledger.monthPattern.hasMatch(key),
    'year' => yearPattern.hasMatch(key),
    _ => false,
  };

  static String previous(String period, String key) {
    final p = key.split('-').map(int.parse).toList();
    return switch (period) {
      'day' => DateTime.utc(p[0], p[1], p[2] - 1).toIso8601String().substring(0, 10),
      'month' => Ledger.month(DateTime.utc(p[0], p[1] - 1)),
      _ => '${p[0] - 1}',
    };
  }

  List<String> _months(String key) => key.length == 4 ? [for (var m = 1; m <= 12; m++) '$key-${'$m'.padLeft(2, '0')}'] : [key.substring(0, 7)];

  Map<String, dynamic> _core(String period, String key) {
    double r(num v) => double.parse(v.toStringAsFixed(2));
    final months = _months(key);
    final scans = [for (final m in months) ...accounts.monthScans(m)].where((s) => '${s['at']}'.startsWith(key)).toList();
    final sales = [for (final m in months) ..._sales(m)].where((s) => s['sandbox'] != true && '${s['at']}'.startsWith(key)).toList();
    final created = [for (final a in accounts.all) '${a['created']}'];
    final double income, expenses;
    if (period == 'day') {
      // اليوم: دخل المتجر وتكلفة Claude والقيود اللي تاريخها هاليوم بالضبط (المتكررة الشهرية ما تنقسم على الأيام).
      final manual = _entries.where((e) => e['date'] == key && e['repeat'] == 'once');
      income =
          sales.fold<double>(0, (t, s) => t + (s['netSar'] as num)) + manual.where((e) => e['kind'] == 'income').fold<double>(0, (t, e) => t + _entrySar(e));
      expenses =
          scans.fold<double>(0, (t, s) => t + ((s['usd'] as num?) ?? 0)) * _sar +
          manual.where((e) => e['kind'] == 'expense').fold<double>(0, (t, e) => t + _entrySar(e)) +
          ((ads?.total(key, key)['spendSar'] as num?) ?? 0);
    } else {
      final st = [for (final m in months) statement(m)];
      income = st.fold<double>(0, (t, s) => t + (s['incomeSar'] as num));
      expenses = st.fold<double>(0, (t, s) => t + (s['expensesSar'] as num));
    }
    return {
      'users': created.where((c) => c.substring(0, min(c.length, key.length)).compareTo(key) <= 0).length,
      'newUsers': created.where((c) => c.startsWith(key)).length,
      'activeUsers': {for (final s in scans) s['user']}.whereType<String>().length,
      'scans': scans.length,
      'newSubs': sales.where((s) => s['type'] != 'RENEWAL' && (s['grossSar'] as num) > 0).length,
      'renewals': sales.where((s) => s['type'] == 'RENEWAL').length,
      'refunds': sales.where((s) => (s['grossSar'] as num) < 0).length,
      'grossSar': r(sales.fold<double>(0, (t, s) => t + (s['grossSar'] as num))),
      'incomeSar': r(income),
      'expensesSar': r(expenses),
      'netSar': r(income - expenses),
      'claudeSar': r(scans.fold<double>(0, (t, s) => t + ((s['usd'] as num?) ?? 0)) * _sar),
      'avgSeconds': scans.isEmpty ? 0 : r(scans.fold<num>(0, (t, s) => t + ((s['ms'] as num?) ?? 0)) / scans.length / 1000),
      'avgConfidence': () {
        final c = scans.map((s) => s['confidence']).whereType<num>().toList();
        return c.isEmpty ? null : r(c.reduce((a, b) => a + b) / c.length);
      }(),
      '_scans': scans,
    };
  }

  Map<String, dynamic> summary(String period, String key, DateTime now) {
    final cur = _core(period, key);
    final prev = _core(period, previous(period, key))..remove('_scans');
    final scans = cur.remove('_scans') as List<Map<String, dynamic>>;
    final species = <String, int>{};
    for (final s in scans) {
      if (s['species'] case final String sp) species[sp] = (species[sp] ?? 0) + 1;
    }
    // الرسم: السنة بالشهور، والشهر بالأيام، واليوم بالساعات.
    final List<String> buckets;
    if (period == 'year') {
      buckets = _months(key);
    } else if (period == 'month') {
      final p = key.split('-').map(int.parse).toList();
      final days = DateTime.utc(p[0], p[1] + 1, 0).day;
      buckets = [for (var d = 1; d <= days; d++) '$key-${'$d'.padLeft(2, '0')}'];
    } else {
      buckets = [for (var h = 0; h < 24; h++) '${key}T${'$h'.padLeft(2, '0')}'];
    }
    final created = [for (final a in accounts.all) '${a['created']}'];
    final series = [
      for (final b in buckets)
        {
          'key': b,
          'scans': scans.where((s) => '${s['at']}'.startsWith(b)).length,
          'newUsers': created.where((c) => c.startsWith(b)).length,
          if (period == 'year') 'netSar': statement(b)['netSar'],
        },
    ];
    return {
      'period': period,
      'key': key,
      'previousKey': previous(period, key),
      ...cur,
      'previous': prev,
      'payingNow': accounts.paying(now),
      'topSpecies': (species.entries.toList()..sort((a, b) => b.value - a.value)).take(10).map((e) => {'id': e.key, 'n': e.value}).toList(),
      'series': series,
      'generated': now.toUtc().toIso8601String(),
    };
  }
}
