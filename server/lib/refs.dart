import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'claude.dart';

/// مكتبة الصور المرجعية: صور قليلة لكل نوع من iNaturalist (رخص CC0 و CC BY فقط)، تنبنى على السيرفر
/// بـ `bash server/eval.sh refs`. المجلد: `dir/رقم حوات/رقم الملاحظة.jpg` مع manifest.json فيه الرخصة وصاحب الصورة.
///
/// تُستخدم في المرحلة الثانية: لما تكون الأنواع متشابهة، نعرض على النموذج صورة السمكة جنب صور الأنواع المرشحة
/// وأقاربها من نفس الجنس، فيقارن بالعين بدل ما يعتمد على ذاكرته.
class RefLibrary {
  RefLibrary._(this._images, this._sci, this._english);

  final Map<String, List<File>> _images;
  final Map<String, String> _sci;
  final Map<String, String> _english;

  /// يرجّع null إذا المجلد غير موجود أو فاضي، فتنطفي المرحلة الثانية بهدوء.
  static RefLibrary? load(String dir, Map<String, dynamic> data) {
    final root = Directory(dir);
    if (!root.existsSync()) return null;
    final images = <String, List<File>>{};
    for (final d in root.listSync().whereType<Directory>()) {
      final files = d.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.jpg')).toList()..sort((a, b) => a.path.compareTo(b.path));
      if (files.isNotEmpty) images[d.uri.pathSegments.where((s) => s.isNotEmpty).last] = files;
    }
    if (images.isEmpty) return null;
    final sci = <String, String>{}, english = <String, String>{};
    for (final s in data['species'] as List) {
      final id = (s['id'] as String).split('-').last;
      sci[id] = s['sci'] as String? ?? '';
      english[id] = s['en'] as String? ?? '';
    }
    return RefLibrary._(images, sci, english);
  }

  int get speciesCount => _images.length;

  String _genus(String id) => (_sci[id] ?? '').split(' ').first;

  /// الأنواع اللي نقارن بينها: المرشحون أولًا، ثم باقي أنواع أجناسهم، بحد أقصى [max]، وبس اللي لها صور.
  List<String> poolFor(List<String> candidates, {int max = 8}) {
    final pool = <String>[];
    void add(String id) {
      if (pool.length < max && !pool.contains(id) && _images.containsKey(id)) pool.add(id);
    }

    candidates.forEach(add);
    final genera = candidates.map(_genus).where((g) => g.isNotEmpty).toSet();
    for (final id in _sci.keys.toList()..sort()) {
      if (genera.contains(_genus(id))) add(id);
    }
    return pool;
  }

  String label(String id) => '${_sci[id]}${(_english[id] ?? '').isEmpty ? '' : ' (${_english[id]})'}';

  /// صورة أو صورتين لكل نوع: صورتين إذا الأنواع قليلة، حتى ما يكبر الطلب.
  Future<List<Photo>> photosFor(String id, {required int perSpecies}) async => [
    for (final f in (_images[id] ?? const <File>[]).take(perSpecies)) Photo(Uint8List.fromList(await f.readAsBytes()), 'image/jpeg'),
  ];
}

/// شكل جواب المرحلة الثانية.
const refsSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['observed_features', 'candidates'],
  'properties': {
    'observed_features': {'type': 'string'},
    'candidates': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['id', 'confidence', 'reason'],
        'properties': {
          'id': {'type': 'string'},
          'confidence': {'type': 'integer'},
          'reason': {'type': 'string'},
        },
      },
    },
  },
};

const refsSystem = '''You are an expert fish taxonomist for the Red Sea and Arabian Gulf.
You get photos of ONE query fish, followed by labelled reference photos of candidate species (several species are close relatives).
Compare the query fish with each reference on diagnostic marks: spot or band pattern and colour, spots on fins, tail shape and margin colour, fin colours, head profile and cheek marks.
Reference photos may show live fish underwater while the query may be a dead fish at a market: colours fade after death, so rely more on pattern and shape than on exact colour.
First write the marks you see on the query fish and how each reference matches or differs in observed_features.
Then give 1 to 3 candidates, best first, using ONLY the reference ids shown. Keep confidence under 60 when the separating marks are not visible.
Write each reason in clear Modern Standard Arabic (one sentence naming the deciding marks).''';

/// جذع رسالة المرحلة الثانية: صور السمكة، ثم لكل نوع مرشح سطر تعريف وصوره.
Future<List<Map<String, Object>>> refsContent(RefLibrary refs, List<Photo> query, List<String> pool) async {
  final per = pool.length <= 4 ? 2 : 1;
  Map<String, Object> image(Photo p) => {
    'type': 'image',
    'source': {'type': 'base64', 'media_type': p.mediaType, 'data': base64Encode(p.bytes)},
  };
  return [
    {'type': 'text', 'text': 'QUERY fish (${query.length} photo${query.length == 1 ? '' : 's'}):'},
    ...query.map(image),
    for (final id in pool) ...[
      {'type': 'text', 'text': 'Reference id $id: ${refs.label(id)}'},
      ...(await refs.photosFor(id, perSpecies: per)).map(image),
    ],
    {'type': 'text', 'text': 'Which reference species is the query fish?'},
  ];
}
