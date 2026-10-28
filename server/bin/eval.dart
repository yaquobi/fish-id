import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/refs.dart';

/// قياس دقة FISH ID بنفس النموذج والتعليمات اللي يستخدمها الخادم.
///
/// species: يجيب صور iNaturalist (درجة بحثية، ويفضّل الأسماك الميتة) لأنواع eval/species.json،
///          ويقيس top-1 و top-3 ومستوى العائلة والزمن.
/// fresh:   يمر على مجلد صور مقسّم حسب الطزاجة (مثل مجموعة FFE من Mendeley) ويقارن تصنيفنا بالتصنيف الحقيقي.
///
/// النتائج: ملخص Markdown على الشاشة، وكل الاستجابات الخام في /out (أو --out) بصيغة JSONL.
Future<void> main(List<String> args) async {
  final opts = _Opts(args);
  final env = Platform.environment;
  final key = env['ANTHROPIC_API_KEY'] ?? '';
  if (key.isEmpty) _die('ANTHROPIC_API_KEY غير موجود. شغّله بـ docker compose run عشان ياخذ ملف .env');
  final data =
      jsonDecode(await File(env['KSAFISH_JSON'] ?? 'data/ksafish.json').readAsString()) as Map<String, dynamic>;
  final ai = FishIdAi(
    key: key,
    speciesList: FishIdAi.speciesListFrom(data),
    model: opts.value('model', env['FISHID_MODEL'] ?? 'claude-opus-5-5'),
    effort: opts.value('effort', env['FISHID_EFFORT'] ?? 'low'),
    prompt: opts.value('prompt', env['FISHID_PROMPT'] ?? 'v1'),
    refs: opts.mode == 'refs' ? null : RefLibrary.load(opts.value('refs', env['FISHID_REFS'] ?? '/nonexistent'), data),
    refsBelow: int.parse(opts.value('refs-below', env['FISHID_REFS_BELOW'] ?? '80')),
  );
  stdout.writeln(
    'النموذج ${ai.model}، الجهد ${ai.effort}، التعليمات ${ai.prompt}، '
    'الصور المرجعية: ${ai.refs == null ? 'لا' : '${ai.refs!.speciesCount} نوعًا، تحت ثقة ${ai.refsBelow}'}',
  );
  final family = {
    for (final s in data['species'] as List) (s['id'] as String).substring(s['id'].length - 4): s['fam'] as String,
  };
  final out = Directory(opts.value('out', '/out'))..createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 16).replaceAll(':', '');

  switch (opts.mode) {
    case 'species':
      await _species(ai, family, opts, File('${out.path}/species-$stamp.jsonl'));
    case 'refs':
      await _buildRefs(data, opts);
    case 'fresh':
      await _fresh(ai, opts, File('${out.path}/fresh-$stamp.jsonl'));
    default:
      _die(
        'الاستخدام: eval species [--per 2] [--list eval/species.json] [--photos /out/species-….jsonl]\n'
        '         eval refs [--dir /data/refs] [--per 3]   (يبني مكتبة الصور المرجعية)\n'
        '         (للقياس: --effort low|medium|high  --prompt v1|v2  --model …  --refs /data/refs  --refs-below 80)\n'
        '         eval fresh --dir /data/ffe [--per 50]',
      );
  }
}

// ---------------------------------------------------------------- species

Future<void> _species(FishIdAi ai, Map<String, String> family, _Opts opts, File log) async {
  final list = (jsonDecode(await File(opts.value('list', 'eval/species.json')).readAsString()) as List).cast<Map>();
  final per = int.parse(opts.value('per', '2'));
  final http = HttpClient()..userAgent = 'FISH-ID-eval/1.0 (hawat.id)';
  final cases = <({String id, String sci, String url, String obs, bool dead})>[];
  // --photos: نفس صور تجربة سابقة، عشان تكون المقارنة بين الإعدادات على نفس الصور بالضبط.
  final reuse = opts.value('photos', '');
  if (reuse.isNotEmpty) {
    for (final line in File(reuse).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
      final j = jsonDecode(line) as Map<String, dynamic>;
      cases.add((id: j['expected'], sci: j['sci'], url: j['photo'], obs: j['observation'], dead: j['dead'] == true));
    }
    stdout.writeln('نعيد ${cases.length} صورة من $reuse');
  } else {
    stdout.writeln('جمع الصور من iNaturalist لـ ${list.length} نوعًا…');
  }
  for (final s in reuse.isEmpty ? list : const <Map>[]) {
    final found = await _inatPhotos(http, s['sci'] as String, per);
    if (found.isEmpty) stdout.writeln('  ما لقينا صور لـ ${s['sci']}');
    for (final f in found) {
      cases.add((id: s['id'] as String, sci: s['sci'] as String, url: f.url, obs: f.obs, dead: f.dead));
    }
  }
  if (cases.isEmpty) _die('ما قدرنا نجيب أي صورة من iNaturalist. تأكد إن السيرفر يوصل لـ api.inaturalist.org');
  stdout.writeln('${cases.length} صورة. نبدأ التحليل…');

  var top1 = 0, top3 = 0, fam = 0, done = 0, failed = 0, compared = 0;
  final times = <int>[];
  final misses = <String>[];
  await _pool(cases, 3, (c) async {
    final sw = Stopwatch()..start();
    Map<String, dynamic>? r;
    String? err;
    try {
      final bytes = await _get(http, c.url);
      r = jsonDecode(await ai.identify([Photo(bytes, 'image/jpeg')])) as Map<String, dynamic>;
    } on FishIdError catch (e) {
      err = e.code;
    } on Exception catch (e) {
      err = '$e';
    }
    sw.stop();
    final ids = [for (final x in (r?['candidates'] as List? ?? const [])) '${x['id']}'.padLeft(4, '0')];
    log.writeAsStringSync(
      '${jsonEncode({'expected': c.id, 'sci': c.sci, 'photo': c.url, 'observation': c.obs, 'dead': c.dead, 'ms': sw.elapsedMilliseconds, 'error': err, 'result': r})}\n',
      mode: FileMode.append,
    );
    done++;
    if (err != null) {
      failed++;
      return;
    }
    times.add(sw.elapsedMilliseconds);
    if (r?['refs_compared'] != null) compared++;
    if (ids.isNotEmpty && ids.first == c.id) top1++;
    if (ids.take(3).contains(c.id)) top3++;
    if (ids.isNotEmpty && family[ids.first] == family[c.id]) fam++;
    if (ids.isEmpty || ids.first != c.id) {
      misses.add('| ${c.sci} (${c.id}) | ${ids.isEmpty ? '—' : ids.first} | ${c.obs} |');
    }
    stdout.write('\r$done/${cases.length}');
  });
  final n = done - failed;
  times.sort();
  stdout.writeln('\n\n## دقة تحديد النوع (${DateTime.now().toUtc().toIso8601String().substring(0, 10)})\n');
  stdout.writeln('- الصور: $n (فشل $failed)، منها ${cases.where((c) => c.dead).length} لأسماك ميتة');
  stdout.writeln('- الصحيح أولًا (top-1): ${_pct(top1, n)}');
  stdout.writeln('- ضمن أول 3 (top-3): ${_pct(top3, n)}');
  stdout.writeln('- العائلة صحيحة: ${_pct(fam, n)}');
  if (compared > 0) stdout.writeln('- انقارنت بالصور المرجعية: ${_pct(compared, n)}');
  if (times.isNotEmpty) stdout.writeln('- الزمن: الوسيط ${(times[times.length ~/ 2] / 1000).toStringAsFixed(1)} ث');
  if (misses.isNotEmpty) {
    stdout.writeln('\n| النوع الصحيح | أول اختيار | الملاحظة |\n|---|---|---|');
    misses.forEach(stdout.writeln);
  }
  stdout.writeln('\nالتفاصيل: ${log.path}');
  http.close();
}

typedef _InatPhoto = ({String url, String obs, bool dead, String license, String attribution});

/// صور بدرجة بحثية برخص مفتوحة. نبدأ بالمعلّمة «ميتة» لأنها أقرب لصور السوق، ونكمّل من الباقي.
Future<List<_InatPhoto>> _inatPhotos(
  HttpClient http,
  String sci,
  int per, {
  String licenses = 'cc0,cc-by,cc-by-nc',
  String size = 'large',
  Set<String> exclude = const {},
}) async {
  final found = <_InatPhoto>[];
  final seen = <String>{};
  for (final dead in [true, false]) {
    if (found.length >= per) break;
    final q = {
      'taxon_name': sci,
      'quality_grade': 'research',
      'photos': 'true',
      'photo_license': licenses,
      'order_by': 'votes',
      'per_page': '30',
      if (dead) ...{'term_id': '17', 'term_value_id': '19'},
    };
    try {
      final j = jsonDecode(
        utf8.decode(await _get(http, Uri.https('api.inaturalist.org', '/v1/observations', q).toString())),
      );
      for (final o in (j['results'] as List)) {
        if (found.length >= per) break;
        // نتأكد إن الملاحظة لنفس النوع، مو نوع قريب أو مرادف.
        if ((o['taxon']?['name'] as String?)?.toLowerCase() != sci.toLowerCase()) continue;
        final photos = o['photos'] as List;
        final obs = 'https://www.inaturalist.org/observations/${o['id']}';
        if (photos.isEmpty || exclude.contains(obs) || !seen.add(obs)) continue;
        final p = photos.first as Map;
        found.add((
          url: (p['url'] as String).replaceFirst('/square.', '/$size.'),
          obs: obs,
          dead: dead,
          license: '${p['license_code'] ?? ''}',
          attribution: '${p['attribution'] ?? ''}',
        ));
      }
    } on Exception catch (e) {
      stderr.writeln('iNaturalist $sci: $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100)); // iNaturalist يطلب طلبًا واحدًا في الثانية تقريبًا
  }
  return found;
}

// ---------------------------------------------------------------- refs

/// يبني مكتبة الصور المرجعية لكل أنواع الموسوعة: 3 صور لكل نوع برخص CC0 و CC BY (تسمح بالاستخدام التجاري)،
/// بحجم متوسط (500 بكسل). صور الاختبار (كل ملاحظة في /out/species-*.jsonl) مستبعدة حتى ما يصير الاختبار غشًا.
/// يكمل من حيث وقف لو انقطع.
Future<void> _buildRefs(Map<String, dynamic> data, _Opts opts) async {
  final dir = Directory(opts.value('dir', '/data/refs'))..createSync(recursive: true);
  final per = int.parse(opts.value('per', '3'));
  final exclude = <String>{};
  final testDir = Directory(opts.value('exclude', '/out'));
  if (testDir.existsSync()) {
    for (final f in testDir.listSync().whereType<File>().where(
      (f) => f.path.contains('species-') && f.path.endsWith('.jsonl'),
    )) {
      for (final l in f.readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
        exclude.add((jsonDecode(l) as Map)['observation'] as String);
      }
    }
  }
  stdout.writeln('نستبعد ${exclude.length} ملاحظة من صور الاختبار');
  final manifestFile = File('${dir.path}/manifest.json');
  final manifest = manifestFile.existsSync()
      ? (jsonDecode(manifestFile.readAsStringSync()) as List).cast<Map>().toList()
      : <Map>[];
  final http = HttpClient()..userAgent = 'FISH-ID-refs/1.0 (hawat.id)';
  final species = (data['species'] as List).cast<Map>();
  var i = 0, total = 0, none = 0;
  for (final s in species) {
    i++;
    final id = (s['id'] as String).split('-').last;
    final sub = Directory('${dir.path}/$id')..createSync();
    final have = sub.listSync().whereType<File>().length;
    if (have >= per) {
      total += have;
      continue;
    }
    final photos = await _inatPhotos(
      http,
      s['sci'] as String,
      per - have,
      licenses: 'cc0,cc-by',
      size: 'medium',
      exclude: exclude,
    );
    if (photos.isEmpty && have == 0) none++;
    for (final p in photos) {
      try {
        final bytes = await _get(http, p.url);
        final name = '${p.obs.split('/').last}.jpg';
        File('${sub.path}/$name').writeAsBytesSync(bytes);
        manifest.add({
          'id': id,
          'file': '$id/$name',
          'observation': p.obs,
          'license': p.license,
          'attribution': p.attribution,
          'dead': p.dead,
        });
        total++;
      } on Exception catch (e) {
        stderr.writeln('${p.url}: $e');
      }
    }
    manifestFile.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(manifest));
    stdout.write('\r$i/${species.length} نوعًا، $total صورة');
  }
  http.close();
  stdout.writeln('\n\nالمكتبة جاهزة: $total صورة في ${dir.path}. أنواع بدون أي صورة مفتوحة الرخصة: $none');
}

// ---------------------------------------------------------------- fresh

/// الفئات الثلاث في FFE: طازجة جدًا، طازجة، غير طازجة. نحدد فئة كل مجلد من اسمه.
String? _classOf(String folder) {
  final f = folder.toLowerCase();
  if (f.contains('not') || f.contains('non') || f.contains('spoil')) return 'not_fresh';
  if (f.contains('high') || f.contains('very')) return 'highly_fresh';
  if (f.contains('fresh')) return 'fresh';
  return null;
}

/// العتبات محددة مسبقًا ومطابقة لمستويات التطبيق (85 و 65)، وما تتعدّل بعد رؤية النتائج.
String _predict(Map<String, dynamic> f) {
  if (f['assessable'] != true) return 'unassessable';
  final s = (f['score'] as num).toInt();
  return s >= 85 ? 'highly_fresh' : (s >= 65 ? 'fresh' : 'not_fresh');
}

Future<void> _fresh(FishIdAi ai, _Opts opts, File log) async {
  final root = Directory(opts.value('dir', '/data/ffe'));
  if (!root.existsSync()) _die('المجلد ${root.path} غير موجود');
  final per = int.parse(opts.value('per', '50'));
  final byClass = <String, List<File>>{};
  for (final e in root.listSync(recursive: true).whereType<File>()) {
    if (!RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(e.path)) continue;
    final parts = e.uri.pathSegments;
    final cls = parts.reversed.skip(1).map(_classOf).firstWhere((c) => c != null, orElse: () => null);
    if (cls != null) (byClass[cls] ??= []).add(e);
  }
  if (byClass.isEmpty) _die('ما لقينا مجلدات باسم Highly Fresh / Fresh / Not Fresh داخل ${root.path}');
  final rnd = Random(42); // عينة ثابتة حتى تتكرر التجربة
  final cases = [
    for (final MapEntry(key: cls, value: files) in byClass.entries)
      ...(files
            ..sort((a, b) => a.path.compareTo(b.path))
            ..shuffle(rnd))
          .take(per)
          .map((f) => (cls: cls, file: f)),
  ];
  stdout.writeln('${cases.length} صورة: ${byClass.map((k, v) => MapEntry(k, min(per, v.length)))}');

  const classes = ['highly_fresh', 'fresh', 'not_fresh'];
  final matrix = {
    for (final a in classes)
      a: {
        for (final p in [...classes, 'unassessable', 'error']) p: 0,
      },
  };
  var done = 0;
  await _pool(cases, 3, (c) async {
    String pred;
    Map<String, dynamic>? r;
    try {
      final bytes = await c.file.readAsBytes();
      final type = c.file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      r = jsonDecode(await ai.identify([Photo(bytes, type)])) as Map<String, dynamic>;
      pred = r['freshness'] is Map<String, dynamic> ? _predict(r['freshness'] as Map<String, dynamic>) : 'unassessable';
    } on Exception {
      pred = 'error';
    }
    matrix[c.cls]![pred] = matrix[c.cls]![pred]! + 1;
    log.writeAsStringSync(
      '${jsonEncode({'file': c.file.path, 'truth': c.cls, 'pred': pred, 'freshness': r?['freshness']})}\n',
      mode: FileMode.append,
    );
    stdout.write('\r${++done}/${cases.length}');
  });

  final total = cases.length;
  final correct = classes.fold(0, (a, c) => a + matrix[c]![c]!);
  final assessed = classes.fold(0, (a, t) => a + classes.fold(0, (b, p) => b + matrix[t]![p]!));
  // «صالحة للبيع» مقابل «غير طازجة»: هذا اللي يهم المشتري فعلًا.
  final binOk = classes.fold(
    0,
    (a, t) => a + classes.fold(0, (b, p) => b + ((t == 'not_fresh') == (p == 'not_fresh') ? matrix[t]![p]! : 0)),
  );
  stdout.writeln('\n\n## مقارنة الطزاجة على ${root.path}\n');
  stdout.writeln('- الدقة (3 فئات) من كل الصور: ${_pct(correct, total)}');
  stdout.writeln('- الدقة (3 فئات) من الصور اللي قدر يقيّمها: ${_pct(correct, assessed)} (قيّم $assessed من $total)');
  stdout.writeln('- طازجة أو غير طازجة (فئتين): ${_pct(binOk, assessed)}');
  stdout.writeln('\n| الحقيقة \\ توقعنا | ${[...classes, 'ما قيّم', 'خطأ'].join(' | ')} |\n|---|---|---|---|---|---|');
  for (final t in classes) {
    stdout.writeln('| $t | ${[...classes, 'unassessable', 'error'].map((p) => matrix[t]![p]).join(' | ')} |');
  }
  stdout.writeln('\nالتفاصيل: ${log.path}');
}

// ---------------------------------------------------------------- helpers

Future<Uint8List> _get(HttpClient http, String url) async {
  final req = await http.getUrl(Uri.parse(url));
  final res = await req.close().timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
  final b = BytesBuilder(copy: false);
  await res.forEach(b.add);
  return b.takeBytes();
}

/// يشغّل [work] على العناصر بعدد محدود في نفس الوقت.
Future<void> _pool<T>(List<T> items, int size, Future<void> Function(T) work) async {
  var i = 0;
  await Future.wait([
    for (var w = 0; w < size; w++)
      () async {
        while (i < items.length) {
          await work(items[i++]);
        }
      }(),
  ]);
}

String _pct(int a, int n) => n == 0 ? '—' : '${(100 * a / n).toStringAsFixed(1)}% ($a من $n)';

Never _die(String msg) {
  stderr.writeln(msg);
  exit(2);
}

class _Opts {
  _Opts(List<String> args) : mode = args.isEmpty ? '' : args.first {
    for (var i = 1; i < args.length - 1; i++) {
      if (args[i].startsWith('--')) _v[args[i].substring(2)] = args[i + 1];
    }
  }
  final String mode;
  final _v = <String, String>{};
  String value(String k, String d) => _v[k] ?? d;
}
