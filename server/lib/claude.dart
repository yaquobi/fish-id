import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// خطأ برسالة عربية تنعرض للمستخدم كما هي.
class FishIdError implements Exception {
  const FishIdError(this.code, this.message, {this.status = 400});
  final String code;
  final String message;
  final int status;
}

/// استدعاء Claude Messages API مباشرة (لا توجد مكتبة Dart رسمية).
class FishIdAi {
  FishIdAi({required this.key, required this.speciesList, this.model = 'claude-opus-5-5', this.effort = 'low'});

  final String key;
  final String model;
  final String effort;

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

  String get _system => '''You are a fish identification and seafood-quality expert for Saudi Arabian waters (Red Sea and Arabian Gulf).
You receive one photo taken with a phone, usually at a fish market or on a boat.
Identify the species ONLY from the KSAFish list below (format: id|scientific name|English name|Saudi local names).
Estimate freshness from what is visible: eye clarity and shape, gill colour, skin shine and slime, discoloration.
Be honest about uncertainty: if a part is not visible, say so, and keep confidence low when the photo is unclear.
Write every text field in clear Modern Standard Arabic that Saudi users understand.
Give 1 to 3 candidates, best first, using ids from the list. score 100 means just caught.
If the fish is clearly not in the list, give your best scientific name in outside_list_guess and no candidates.

KSAFish list:
$speciesList''';

  static const schema = {
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
        'required': ['assessable', 'score', 'level', 'eyes', 'gills', 'skin', 'other', 'summary'],
        'properties': {
          'assessable': {'type': 'boolean'},
          'score': {'type': 'integer'},
          'level': {
            'type': 'string',
            'enum': ['طازجة جدًا', 'طازجة', 'متوسطة', 'غير طازجة', 'غير معروف'],
          },
          'eyes': {'type': 'string'},
          'gills': {'type': 'string'},
          'skin': {'type': 'string'},
          'other': {'type': 'string'},
          'summary': {'type': 'string'},
        },
      },
      'photo_tip': {'type': 'string'},
    },
  };

  Map<String, Object> requestBody(Uint8List image, String mediaType) => {
        'model': model,
        'max_tokens': 4000,
        'output_config': {
          'effort': effort,
          'format': {'type': 'json_schema', 'schema': schema},
        },
        'fallbacks': 'default',
        'system': [
          // القائمة ثابتة، فتنحفظ مؤقتًا وتنقص تكلفة كل صورة بعد الأولى.
          {'type': 'text', 'text': _system, 'cache_control': {'type': 'ephemeral'}},
        ],
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Encode(image)},
              },
              {'type': 'text', 'text': 'حلّل هذه الصورة.'},
            ],
          },
        ],
      };

  /// يرجّع نتيجة التحليل كنص JSON بالشكل المعرّف في [schema].
  Future<String> identify(Uint8List image, String mediaType) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(_url));
      req.headers
        ..set('x-api-key', key)
        ..set('anthropic-version', '2026-10-21')
        ..set('anthropic-beta', 'server-side-fallback-2026-07-01')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(requestBody(image, mediaType))));
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
      jsonDecode(out); // يتأكد إنه JSON سليم قبل ما يوصل للتطبيق.
      return out;
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
