import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'qim.dart';

/// صورة واحدة من صور السمكة.
class Photo {
  const Photo(this.bytes, this.mediaType);
  final Uint8List bytes;
  final String mediaType;
}

/// خطأ برسالة عربية تنعرض للمستخدم كما هي.
class FishIdError implements Exception {
  const FishIdError(this.code, this.message, {this.status = 400});
  final String code;
  final String message;
  final int status;
}

/// استدعاء Claude Messages API مباشرة (لا توجد مكتبة Dart رسمية).
class FishIdAi {
  FishIdAi({required this.key, required this.speciesList, this.model = 'claude-opus-5-5', this.effort = 'low', this.prompt = 'v1'});

  final String key;
  final String model;
  final String effort;

  /// نسخة التعليمات: v1 الحالية، و v2 تجبر النموذج يحدد العائلة والجنس أولًا ويقارن الأنواع المتشابهة بعلاماتها.
  /// نقارن بينها بأداة القياس (bin/eval.dart) على نفس الصور قبل ما نغيّر الافتراضي.
  final String prompt;

  /// سطر لكل نوع: رقم حوات (آخر 4 أرقام)|الاسم العلمي|الإنجليزي|الأسماء المحلية.
  final String speciesList;

  static const _url = 'https://api.anthropic.com/v1/messages';

  /// يبني قائمة الأنواع من ملف ksafish.json نفسه اللي يستخدمه التطبيق.
  static String speciesListFrom(Map<String, dynamic> data) => [
    for (final s in data['species'] as List)
      [
        (s['id'] as String).split('-').last,
        s['sci'],
        s['en'],
        [s['red'], s['gulf']].where((n) => (n as String? ?? '').isNotEmpty).join(' | '),
      ].join('|'),
  ].join('\n');

  String get _system =>
      '''You are a fish identification and seafood-quality expert for Saudi Arabian waters (Red Sea and Arabian Gulf).
You receive 1 to 3 phone photos of the SAME fish, usually at a fish market or on a boat (for example the whole fish, a close-up of the eye, and the open gills).
Identify the species ONLY from the KSAFish list below (format: id|scientific name|English name|Saudi local names).
Give 1 to 3 candidates, best first, using ids from the list. If the fish is clearly not in the list, give your best scientific name in outside_list_guess and no candidates.
${prompt == 'v2' ? _lookAlikes : ''}
Freshness: score each visual Quality Index Method (QIM) attribute in freshness.qim using these demerit points (0 = perfectly fresh).
Use -1 when that part is not visible or cannot be judged from the photos. Never guess a part you cannot see.
${qimPromptTable()}
Smell and stiffness cannot be judged from photos; mention them in freshness.manual_checks when they would matter.
Set freshness.assessable to false for live fish, cooked, frozen-solid or filleted fish, or when almost nothing is visible.
estimated_days_min and estimated_days_max: your estimate of days since catch if kept on ice, considering the species and warm-water spoilage; use -1 when not assessable.
Fill eyes, gills and skin with what you actually saw; summary is one sentence of practical advice for a buyer.

Be honest about uncertainty and keep confidence low when the photo is unclear.
Write every text field in clear Modern Standard Arabic that Saudi users understand.

KSAFish list:
$speciesList''';

  static const _lookAlikes = '''
Work like a taxonomist, and write your notes in observed_features before choosing:
1. Family and genus from body shape, mouth, fins and tail shape.
2. List every species of that genus in the KSAFish list, then compare them on diagnostic marks you can actually see: spot or band pattern and colour, spots on fins, tail edge (rounded, truncate, forked) and its margin colour, fin colours, head profile, lines or marks on the cheek.
3. Pick the species whose marks match. Do not default to the most common or best-known species of a genus. If the marks that separate two congeners are not visible, put both as candidates and keep confidence under 60.
''';

  static Map<String, Object> schemaFor(String prompt) => prompt == 'v2'
      ? {
          ...schema,
          'required': ['observed_features', ...(schema['required'] as List)],
          'properties': {
            'observed_features': {'type': 'string'},
            ...(schema['properties'] as Map),
          },
        }
      : schema;

  static final schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['is_fish', 'subject', 'candidates', 'outside_list_guess', 'freshness', 'photo_tip'],
    'properties': {
      'is_fish': {'type': 'boolean'},
      'subject': {'type': 'string'},
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
      'outside_list_guess': {'type': 'string'},
      'freshness': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'assessable', 'qim', 'eyes', 'gills', 'skin', 'other', 'manual_checks', //
          'estimated_days_min', 'estimated_days_max', 'summary',
        ],
        'properties': {
          'assessable': {'type': 'boolean'},
          'qim': {
            'type': 'object',
            'additionalProperties': false,
            'required': [for (final a in qimAttributes) a.key],
            'properties': {
              for (final a in qimAttributes) a.key: {'type': 'integer'},
            },
          },
          'eyes': {'type': 'string'},
          'gills': {'type': 'string'},
          'skin': {'type': 'string'},
          'other': {'type': 'string'},
          'manual_checks': {'type': 'string'},
          'estimated_days_min': {'type': 'integer'},
          'estimated_days_max': {'type': 'integer'},
          'summary': {'type': 'string'},
        },
      },
      'photo_tip': {'type': 'string'},
    },
  };

  Map<String, Object> requestBody(List<Photo> photos) => {
    'model': model,
    'max_tokens': 4000,
    'output_config': {
      'effort': effort,
      'format': {'type': 'json_schema', 'schema': schemaFor(prompt)},
    },
    'fallbacks': 'default',
    'system': [
      // القائمة ثابتة، فتنحفظ مؤقتًا وتنقص تكلفة كل صورة بعد الأولى.
      {
        'type': 'text',
        'text': _system,
        'cache_control': {'type': 'ephemeral'},
      },
    ],
    'messages': [
      {
        'role': 'user',
        'content': [
          for (final p in photos)
            {
              'type': 'image',
              'source': {'type': 'base64', 'media_type': p.mediaType, 'data': base64Encode(p.bytes)},
            },
          {'type': 'text', 'text': photos.length == 1 ? 'حلّل هذه الصورة.' : 'حلّل هذه الصور، وكلها لنفس السمكة.'},
        ],
      },
    ],
  };

  /// يرجّع نتيجة التحليل كنص JSON بالشكل المعرّف في [schema]، مع الدرجة والتصنيف المحسوبة من نقاط QIM.
  Future<String> identify(List<Photo> photos) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(_url));
      req.headers
        ..set('x-api-key', key)
        ..set('anthropic-version', '2026-10-21')
        ..set('anthropic-beta', 'server-side-fallback-2026-07-01')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(requestBody(photos))));
      final res = await req.close().timeout(const Duration(seconds: 90));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429 || res.statusCode == 529) throw const FishIdError('busy', 'الخدمة مشغولة، حاول بعد شوي', status: 503);
      if (res.statusCode >= 300) {
        stderr.writeln('FishId: Claude ${res.statusCode}: $text');
        throw const FishIdError('fishid_error', 'تعذّر تحليل الصورة، حاول مرة ثانية', status: 502);
      }
      final msg = jsonDecode(text) as Map<String, dynamic>;
      stdout.writeln('FishId: ${msg['model']} usage ${jsonEncode(msg['usage'])}');
      if (msg['stop_reason'] == 'refusal') throw const FishIdError('fishid_refused', 'ما قدرنا نحلل هذه الصورة، جرّب صورة ثانية');
      if (msg['stop_reason'] == 'max_tokens') throw const FishIdError('fishid_error', 'تعذّر تحليل الصورة، حاول مرة ثانية', status: 502);
      final out = (msg['content'] as List).where((b) => b['type'] == 'text').map((b) => b['text'] as String).join();
      final result = jsonDecode(out) as Map<String, dynamic>;
      if (result['freshness'] case final Map<String, dynamic> f) completeFreshness(f);
      return jsonEncode(result);
    } on FishIdError {
      rethrow;
    } on FormatException {
      throw const FishIdError('fishid_error', 'تعذّر تحليل الصورة، حاول مرة ثانية', status: 502);
    } on Exception catch (e) {
      stderr.writeln('FishId: $e');
      throw const FishIdError('fishid_error', 'تعذّر الاتصال بخدمة التحليل، حاول مرة ثانية', status: 502);
    } finally {
      client.close();
    }
  }
}
