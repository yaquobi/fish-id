import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n.dart';
import 'box.dart';

/// المستندات الرسمية اللي تطلع من الجوال PDF: تقرير الزيارة التفتيشية، وكشف الحراج للدلّال.
/// نفس شكل كشوف لوحة الأدمن: ترويسة كحلية بخط ذهبي، وجداول بخطوط رفيعة، بدون زوايا دائرية.
abstract final class Reports {
  static const _navy = PdfColor.fromInt(0xFF0B2236);
  static const _gold = PdfColor.fromInt(0xFFF2C14E);
  static const _goldInk = PdfColor.fromInt(0xFFC9971F);
  static const _muted = PdfColor.fromInt(0xFF5B6B79);
  static const _line = PdfColor.fromInt(0xFFEAEEF2);
  static const _bad = PdfColor.fromInt(0xFFB3261E);
  static const _good = PdfColor.fromInt(0xFF17804F);
  static const _head = PdfColor.fromInt(0xFFEEF2F6);

  static pw.ThemeData? _cached;

  static Future<pw.ThemeData> _theme() async => _cached ??= pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/pdf/Tajawal-Regular-pdf.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/pdf/Tajawal-Bold-pdf.ttf')),
  );

  static pw.TextDirection get _dir => L10n.en ? pw.TextDirection.ltr : pw.TextDirection.rtl;

  /// التاريخ والوقت بتوقيت السعودية (UTC+3) بصيغة ثابتة.
  static String when(DateTime t) {
    final k = t.toUtc().add(const Duration(hours: 3));
    String two(int n) => '$n'.padLeft(2, '0');
    return '${k.year}-${two(k.month)}-${two(k.day)} ${two(k.hour)}:${two(k.minute)}';
  }

  static pw.Widget _header(String title, String en, String number) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 3)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.RichText(
              textDirection: pw.TextDirection.ltr,
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'FISH ',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20, color: _navy),
                  ),
                  pw.TextSpan(
                    text: 'ID',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20, color: _goldInk),
                  ),
                ],
              ),
            ),
            pw.Text(
              tr('إحدى مبادرات منظومة حوات', 'A HUWAT initiative'),
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _navy),
            ),
            pw.Text(
              en,
              textDirection: pw.TextDirection.ltr,
              style: const pw.TextStyle(fontSize: 8, color: _muted, letterSpacing: 1.5),
            ),
            if (number.isNotEmpty)
              pw.Text(
                number,
                textDirection: pw.TextDirection.ltr,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy),
              ),
          ],
        ),
      ],
    ),
  );

  static pw.Widget _goldBar() =>
      pw.Container(width: 70, height: 3, color: _gold, margin: const pw.EdgeInsets.only(top: 2, bottom: 14));

  static pw.Widget _section(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
    child: pw.Row(
      children: [
        pw.Container(width: 4, height: 12, color: _gold),
        pw.SizedBox(width: 6),
        pw.Text(
          t,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _navy),
        ),
      ],
    ),
  );

  static pw.Widget _row(String k, String v, {PdfColor? color, bool ltr = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _line)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: _muted)),
        pw.SizedBox(width: 16),
        pw.Flexible(
          child: pw.Text(
            v.isEmpty ? '—' : v,
            textAlign: L10n.en ? pw.TextAlign.right : pw.TextAlign.left,
            textDirection: ltr ? pw.TextDirection.ltr : null,
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: color ?? _navy),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _footer(String note) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 18),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _line)),
    ),
    child: pw.Text(note, style: const pw.TextStyle(fontSize: 8, color: _muted)),
  );

  static const violationNames = {
    'name': ('تسمية مضللة للصنف', 'Misleading species name'),
    'fresh': ('سمك غير طازج', 'Not fresh'),
    'price': ('السعر غير معلن أو مخالف', 'Price not shown or wrong'),
    'hygiene': ('النظافة والتبريد', 'Hygiene and chilling'),
    'other': ('أخرى', 'Other'),
  };

  static String violationName(String k) {
    final v = violationNames[k];
    return v == null ? k : tr(v.$1, v.$2);
  }

  static String decisionName(String d) => switch (d) {
    'violation' => tr('مخالفة', 'Violation'),
    'followup' => tr('يحتاج متابعة', 'Follow-up needed'),
    _ => tr('سليم', 'Compliant'),
  };

  /// تقرير الزيارة التفتيشية: البيانات، المكتوب مقابل المرجّح، القرار، الملاحظة، الموقع، والصور.
  static Future<Uint8List> inspection(Map<String, dynamic> v, {List<Uint8List> photos = const []}) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme, title: '${v['ref'] ?? ''}', author: 'FISH ID');
    final at = DateTime.tryParse('${v['at'] ?? ''}') ?? DateTime.now();
    final decision = '${v['decision'] ?? 'ok'}';
    final violations = [for (final t in (v['violations'] as List? ?? const [])) violationName('$t')];
    final price = v['labelPrice'];
    final lat = v['lat'], lng = v['lng'];
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: _dir,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          _header(tr('تقرير زيارة تفتيشية', 'Inspection visit report'), 'INSPECTION REPORT', '${v['ref'] ?? ''}'),
          _goldBar(),
          _section(tr('بيانات الزيارة', 'Visit')),
          _row(
            tr('المفتش', 'Inspector'),
            '${v['inspectorName'] ?? ''}${'${v['branch'] ?? ''}'.isEmpty ? '' : ' · ${v['branch']}'}',
          ),
          _row(tr('الجهة', 'Agency'), '${v['agency'] ?? ''}'),
          _row(tr('التاريخ والوقت', 'Date and time'), when(at), ltr: true),
          _row(tr('السوق', 'Market'), '${v['market'] ?? ''}${'${v['city'] ?? ''}'.isEmpty ? '' : ' · ${v['city']}'}'),
          _row(tr('المحل', 'Shop'), '${v['shop'] ?? ''}'),
          if (lat is num && lng is num)
            _row(tr('الموقع', 'Location'), '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}', ltr: true),
          _section(tr('نتيجة الفحص', 'Check')),
          _row(
            tr('المكتوب على اللوحة', 'Shop label'),
            '${v['labelName'] ?? ''}${price is num ? ' · ${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)} ${tr('ر.س/كجم', 'SAR/kg')}' : ''}',
          ),
          _row(
            tr('الصنف المرجّح (استرشادي)', 'Likely species (advisory)'),
            '${v['speciesName'] ?? ''}${'${v['sci'] ?? ''}'.isEmpty ? '' : ' (${v['sci']})'}${v['confidence'] is num ? ' · ${v['confidence']}%' : ''}',
          ),
          if (v['match'] is bool)
            _row(
              tr('مطابقة اللوحة', 'Label match'),
              v['match'] == true ? tr('مطابق', 'Matches') : tr('ما يطابق', 'Does not match'),
              color: v['match'] == true ? _good : _bad,
            ),
          if (v['freshness'] is num)
            _row(
              tr('الطزاجة', 'Freshness'),
              '${v['freshness']}/100${'${v['grade'] ?? ''}'.isEmpty ? '' : ' · ${v['grade']}'}',
            ),
          _section(tr('قرار المفتش', 'Inspector decision')),
          _row(
            tr('النتيجة', 'Result'),
            decisionName(decision),
            color: decision == 'violation'
                ? _bad
                : decision == 'ok'
                ? _good
                : _goldInk,
          ),
          if (violations.isNotEmpty) _row(tr('نوع المخالفة', 'Violation'), violations.join('، ')),
          if ('${v['note'] ?? ''}'.isNotEmpty) _row(tr('ملاحظة المفتش', 'Inspector note'), '${v['note']}'),
          if (photos.isNotEmpty) ...[
            _section(tr('الصور', 'Photos')),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in photos.take(3))
                  pw.Container(width: 160, height: 160, child: pw.Image(pw.MemoryImage(p), fit: pw.BoxFit.cover)),
              ],
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    tr('توقيع المفتش', 'Inspector signature'),
                    style: const pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                  pw.SizedBox(height: 26),
                  pw.Container(width: 150, height: .7, color: _muted),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    tr('توقيع صاحب المحل', 'Shop representative'),
                    style: const pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                  pw.SizedBox(height: 26),
                  pw.Container(width: 150, height: .7, color: _muted),
                ],
              ),
            ],
          ),
          _footer(
            tr(
              'صادر من تطبيق FISH ID. التعرّف على الصنف والطزاجة بالذكاء الاصطناعي استرشادي، والقرار النهائي للمفتش. الرقم المرجعي محفوظ في لوحة الجهة.',
              'Issued by the FISH ID app. AI species and freshness results are advisory; the inspector makes the final decision. The reference is stored on the agency dashboard.',
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// كشف الحراج للدلّال: الأنواع وأعدادها التقريبية وحجمها وطزاجتها، مع صورة الصندوق.
  static Future<Uint8List> haraj(
    BoxResult r, {
    String seller = '',
    String market = '',
    Uint8List? photo,
    DateTime? at,
  }) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme, title: tr('كشف حراج', 'Auction sheet'), author: 'FISH ID');
    final t = at ?? DateTime.now();
    final number = 'H-${when(t).replaceAll(RegExp(r'[^0-9]'), '').substring(2, 12)}';
    List<T> cols<T>(List<T> l) => L10n.en ? l : l.reversed.toList();
    const widths = <pw.TableColumnWidth>[
      pw.FixedColumnWidth(22),
      pw.FlexColumnWidth(3),
      pw.FlexColumnWidth(1.4),
      pw.FlexColumnWidth(1.6),
      pw.FlexColumnWidth(1.2),
      pw.FlexColumnWidth(1.4),
    ];
    pw.Widget cell(String s, {bool head = false, bool num = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        s,
        textDirection: num ? pw.TextDirection.ltr : null,
        textAlign: L10n.en ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: head ? 9 : 10.5,
          fontWeight: head ? pw.FontWeight.bold : null,
          color: head ? _navy : null,
        ),
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: _dir,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          _header(tr('كشف حراج', 'Auction sheet'), 'HARAJ SHEET', number),
          _goldBar(),
          _row(tr('التاريخ والوقت', 'Date and time'), when(t), ltr: true),
          if (market.isNotEmpty) _row(tr('السوق', 'Market'), market),
          if (seller.isNotEmpty) _row(tr('البائع أو القارب', 'Seller or boat'), seller),
          _row(tr('مجموع الأسماك (تقريبي)', 'Total fish (approx.)'), '${r.total}'),
          if (r.overallFreshness >= 0) _row(tr('الطزاجة العامة', 'Overall freshness'), '${r.overallFreshness}/100'),
          _section(tr('الأنواع', 'Species')),
          pw.Table(
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line)),
            // pw.Table ما يقلب الأعمدة مع اتجاه الصفحة، فنقلبها بنفسنا للعربي.
            columnWidths: {for (final (k, w) in cols(widths).indexed) k: w},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: _head,
                  border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1.5)),
                ),
                children: cols([
                  cell('#', head: true),
                  cell(tr('النوع', 'Species'), head: true),
                  cell(tr('العدد', 'Count'), head: true),
                  cell(tr('المدى', 'Range'), head: true),
                  cell(tr('الحجم', 'Size'), head: true),
                  cell(tr('الطزاجة', 'Freshness'), head: true),
                ]),
              ),
              for (final (k, i) in r.items.indexed)
                pw.TableRow(
                  children: cols([
                    cell('${k + 1}', num: true),
                    cell(i.name),
                    cell('${i.count}', num: true),
                    cell(i.rangeLabel, num: true),
                    cell(i.sizeLabel),
                    cell(i.freshness >= 0 ? '${i.freshness}/100' : '—', num: true),
                  ]),
                ),
            ],
          ),
          if (r.summary.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(r.summary, style: const pw.TextStyle(fontSize: 10)),
            ),
          if (photo != null) ...[
            _section(tr('صورة الصندوق', 'Box photo')),
            pw.Container(
              height: 220,
              alignment: pw.Alignment.centerRight,
              child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.contain),
            ),
          ],
          _footer(
            tr(
              'صادر من تطبيق FISH ID. الأعداد والطزاجة تقديرية من الصورة بالذكاء الاصطناعي، وتتأكد منها قبل البيع.',
              'Issued by the FISH ID app. Counts and freshness are AI estimates from the photo; check them before selling.',
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
