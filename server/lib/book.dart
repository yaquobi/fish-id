import 'dart:convert';
import 'dart:io';

/// أرشيف كتاب «أسماك المياه الإقليمية للمملكة في البحر الأحمر» (مركز أبحاث الثروة السمكية بجدة، 2011):
/// صور كل نوع واسمه العلمي والإنجليزي وأسماءه المحلية، يستخرجها tool/book_extract.py في `dir`.
/// كل نوع ينربط برقمه في الموسوعة من اسمه العلمي (ونسامح غلطة حرفين، الكتاب فيه مثل Epinphelus).
class BookArchive {
  BookArchive._(this.dir, this._species);

  final String dir;
  final List<Map<String, dynamic>> _species;

  static final _part = RegExp(r'^[0-9]{3}_[A-Za-z_]{1,80}$');
  static final _file = RegExp(r'^[1-3]\.jpg$');

  /// null إذا الأرشيف مو موجود. [sciToId] الاسم العلمي (بحروف صغيرة) ← رقم الموسوعة (4 أرقام).
  static BookArchive? open(String dir, Map<String, String> sciToId) {
    final f = File('$dir/index.json');
    if (!f.existsSync()) return null;
    final index = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final list = [for (final s in index['species'] as List) (s as Map).cast<String, dynamic>()];
    for (final s in list) {
      s['ksafish'] = match('${s['sci']}', sciToId);
    }
    return BookArchive._(dir, list);
  }

  /// رقم الموسوعة للاسم العلمي: مطابقة كاملة، وإلا أقرب اسم بفرق حرفين أو أقل.
  static String? match(String sci, Map<String, String> sciToId) {
    final s = sci.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final exact = sciToId[s];
    if (exact != null) return exact;
    String? best;
    var bestD = 3;
    for (final e in sciToId.entries) {
      if ((e.key.length - s.length).abs() >= bestD) continue;
      final d = _distance(s, e.key, bestD);
      if (d < bestD) {
        bestD = d;
        best = e.value;
      }
    }
    return best;
  }

  static int _distance(String a, String b, int cap) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      var rowMin = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
        if (cur[j] < rowMin) rowMin = cur[j];
      }
      if (rowMin >= cap) return cap;
      prev = cur;
    }
    return prev[b.length];
  }

  List<Map<String, dynamic>> get species => _species;

  File? file(String folder, String name) {
    if (!_part.hasMatch(folder) || !_file.hasMatch(name)) return null;
    final f = File('$dir/$folder/$name');
    return f.existsSync() ? f : null;
  }
}
