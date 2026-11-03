import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/fish_id_api.dart';
import '../data/reports.dart';
import '../l10n.dart';
import '../theme.dart';
import 'inspection_screen.dart';

/// الوضع الرسمي للمفتشين: الدخول برمز الجهة (GOV-XXXXXX)، وجولة اليوم (السوق الحالي)، والزيارات.
/// المفتش يفحص بلا حد، وكل زيارة تنحفظ برقم مرجعي وتطلع في لوحة الجهة.
class InspectorScreen extends StatefulWidget {
  const InspectorScreen({super.key});

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen> {
  final _code = TextEditingController();
  final _market = TextEditingController();
  final _city = TextEditingController();
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>>? _visits;

  @override
  void initState() {
    super.initState();
    _loadMarket();
    if (FishIdApi.gov.value != null) _refresh();
  }

  @override
  void dispose() {
    _code.dispose();
    _market.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _loadMarket() async {
    try {
      final p = await SharedPreferences.getInstance();
      _market.text = p.getString('gov_market') ?? '';
      _city.text = p.getString('gov_city') ?? '';
    } on Object {
      return;
    }
  }

  Future<void> _saveMarket() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('gov_market', _market.text.trim());
      await p.setString('gov_city', _city.text.trim());
    } on Object {
      return;
    }
  }

  Future<void> _refresh() async {
    try {
      final v = await FishIdApi.govVisits();
      if (mounted) setState(() => _visits = v);
    } on FishIdException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _join() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FishIdApi.govJoin(_code.text);
      await FishIdApi.refreshRemaining();
      await _refresh();
    } on FishIdException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('الخروج من الوضع الرسمي؟', 'Leave official mode?')),
        content: Text(
          tr(
            'الجوال يرجع حساب عادي. تقدر ترجع بنفس الرمز في أي وقت.',
            'This phone goes back to a normal account. You can sign in again with the same code.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: Text(tr('خروج', 'Leave'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FishIdApi.govLeave();
      if (mounted) Navigator.of(context).pop();
    } on FishIdException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _newVisit() async {
    if (_market.text.trim().isEmpty) {
      setState(() => _error = tr('اكتب اسم السوق أول', 'Enter the market name first'));
      return;
    }
    setState(() => _error = null);
    await _saveMarket();
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InspectionScreen(market: _market.text.trim(), city: _city.text.trim()),
      ),
    );
    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('الوضع الرسمي', 'Official mode'))),
    body: ValueListenableBuilder(
      valueListenable: FishIdApi.gov,
      builder: (context, gov, _) => gov == null ? _signIn() : _home(gov),
    ),
  );

  Widget _signIn() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(tr('دخول المفتشين', 'Inspector sign-in'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        tr(
          'للمفتشين في الجهات الحكومية المشتركة. اكتب الرمز اللي أعطاك إياه مشرفك.',
          'For inspectors of subscribed government agencies. Enter the code your supervisor gave you.',
        ),
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 20, letterSpacing: 2),
        decoration: InputDecoration(hintText: 'GOV-XXXXXX', border: const OutlineInputBorder(), errorText: _error),
        onSubmitted: (_) => _join(),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _busy ? null : _join, child: Text(tr('دخول', 'Sign in'))),
      const SizedBox(height: 16),
      _Info(
        text: tr(
          'بعد الدخول: فحص بلا حد، وزيارة تفتيشية تقارن المكتوب على لوحة المحل بالصنف الحقيقي، وتقرير رسمي PDF. الذكاء الاصطناعي يساعد بس، والقرار لك.',
          'After signing in: unlimited scans, inspection visits that compare the shop label with the real species, and an official PDF report. AI only assists; the decision is yours.',
        ),
      ),
    ],
  );

  Widget _home(Map<String, dynamic> g) {
    final visits = _visits;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${g['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      _Badge(active: g['active'] == true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${g['agency']}${'${g['branch'] ?? ''}'.isEmpty ? '' : ' · ${g['branch']}'}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const Divider(height: 24),
                  _Kv(tr('الرمز', 'Code'), '${g['code']}', ltr: true),
                  _Kv(tr('زيارات اليوم', 'Visits today'), '${g['today'] ?? 0}'),
                  _Kv(tr('زيارات الشهر', 'Visits this month'), '${g['month'] ?? 0}'),
                  _Kv(tr('الفحوصات', 'Scans'), tr('بلا حد', 'Unlimited')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('جولة اليوم', "Today's round"), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _market,
                    decoration: InputDecoration(
                      labelText: tr('السوق', 'Market'),
                      hintText: tr('مثل: سوق السمك المركزي (البنقلة)', 'e.g. Central fish market'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _city,
                    decoration: InputDecoration(labelText: tr('المدينة', 'City'), border: const OutlineInputBorder()),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: const TextStyle(color: AppColors.bad)),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: g['active'] == true ? _newVisit : null,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.navy),
                    icon: const Icon(Icons.assignment_outlined),
                    label: Text(tr('زيارة تفتيشية جديدة', 'New inspection visit')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(tr('آخر الزيارات', 'Recent visits'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          if (visits == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('ما فيه زيارات للحين.', 'No visits yet.'), style: const TextStyle(color: AppColors.muted)),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final v in visits.take(30))
                    ListTile(
                      title: Text('${v['shop']}'),
                      subtitle: Text(
                        '${v['ref']} · ${Reports.when(DateTime.tryParse('${v['at']}') ?? DateTime.now())}',
                        textDirection: TextDirection.ltr,
                        textAlign: L10n.en ? TextAlign.left : TextAlign.right,
                      ),
                      trailing: _Decision('${v['decision']}'),
                      onTap: () async {
                        final pdf = await Reports.inspection({...v, 'agency': g['agency']});
                        await Printing.sharePdf(bytes: pdf, filename: '${v['ref']}.pdf');
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout),
            label: Text(tr('الخروج من الوضع الرسمي', 'Leave official mode')),
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.ltr = false});
  final String k;
  final String v;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(k, style: const TextStyle(color: AppColors.muted)),
        ),
        Text(
          v,
          textDirection: ltr ? TextDirection.ltr : null,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(border: Border.all(color: active ? AppColors.gold : AppColors.bad)),
    child: Text(
      active ? tr('رسمي', 'OFFICIAL') : tr('موقوف', 'STOPPED'),
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? AppColors.navy : AppColors.bad),
    ),
  );
}

class _Decision extends StatelessWidget {
  const _Decision(this.d);
  final String d;

  @override
  Widget build(BuildContext context) {
    final color = d == 'violation'
        ? AppColors.bad
        : d == 'followup'
        ? AppColors.warn
        : AppColors.good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: color.withValues(alpha: .12),
      child: Text(
        Reports.decisionName(d),
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    color: AppColors.gold.withValues(alpha: .18),
    child: Text(text, style: const TextStyle(height: 1.5)),
  );
}
