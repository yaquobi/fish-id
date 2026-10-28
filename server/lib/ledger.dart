import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'accounts.dart';
import 'claude.dart';

/// المحاسبة: الدخل والمصاريف والصافي لكل شهر، بالريال. الملفات في نفس مجلد الحسابات:
///
/// - `sales/YYYY-MM.jsonl`: عمليات المتجر من أحداث RevenueCat (اشتراك، تجديد، استرجاع) بالمبلغ وضريبته وعمولة المتجر.
/// - `ledger.json`: قيود يدخلها الأدمن، دخل أو مصروف، مرة وحدة أو يتكرر كل شهر أو كل سنة (مثل الخادم والدومين).
///
/// وتكلفة Claude تنحسب لحالها من سجل الفحوصات، ورسوم RevenueCat (1% بعد أول 2,500 دولار بالشهر) من المبيعات.
class Ledger {
  Ledger._(this.accounts, this._entries);

  final AccountStore accounts;
  final List<Map<String, dynamic>> _entries;

  String get dir => accounts.dir;

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
    return Ledger._(accounts, list);
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
      // بدون نسب من RevenueCat: ضريبة القيمة المضافة 15% داخل السعر، وعمولة Google 15% من الباقي.
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
      final p = byProduct.putIfAbsent('${s['product']}', () => {'n': 0, 'refunds': 0, 'grossSar': 0.0, 'taxSar': 0.0, 'feeSar': 0.0, 'netSar': 0.0});
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
        'provider': 'Google Play',
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
        if (statement(month(DateTime.utc(y, mo - i))) case final s) {'month': s['month'], 'incomeSar': s['incomeSar'], 'expensesSar': s['expensesSar'], 'netSar': s['netSar']},
    ];
  }

  Map<String, dynamic> report(String m) => {...statement(m), 'history': history(m), 'entries': entries()};

  Future<void> _queue = Future.value();

  Future<void> _save() {
    final text = jsonEncode(_entries);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/ledger.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/ledger.json');
    });
  }
}
