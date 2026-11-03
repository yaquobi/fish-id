import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'qim.dart';
import 'refs.dart';

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

/// مفتاح Zone للغة الرد: 'en' يطلب النصوص بالإنجليزي، وغيرها بالعربي (التطبيق يرسلها في x-fishid-lang).
const langKey = #fishIdLang;

/// مفتاح Zone لقائمة يتجمع فيها استهلاك كل استدعاء لـ Claude خلال فحص واحد، عشان نحسب تكلفته.
const usageKey = #fishIdUsage;

/// الأسعار بالدولار لكل مليون توكن: إدخال، إخراج، قراءة من الكاش، كتابة في الكاش.
const _prices = {'claude-opus-5-5': (4.0, 20.0, 0.20, 5.0), 'claude-sonnet-5-5': (2.0, 10.0, 0.20, 2.5), 'claude-haiku-5-5': (0.10, 0.50, 0.01, 0.125)};

/// تكلفة الاستدعاءات بالدولار من سطور usage اللي يرجعها Claude.
double usageCost(List<Map<String, dynamic>> usage) {
  var usd = 0.0;
  for (final u in usage) {
    final model = '${u['model']}';
    final p = _prices.entries.firstWhere((e) => model.startsWith(e.key), orElse: () => _prices.entries.first).value;
    int n(String k) => (u[k] as num?)?.toInt() ?? 0;
    // الوضع السريع بضعف السعر.
    final speed = u['speed'] == 'fast' ? 2 : 1;
    usd += speed * (n('input_tokens') * p.$1 + n('output_tokens') * p.$2 + n('cache_read_input_tokens') * p.$3 + n('cache_creation_input_tokens') * p.$4) / 1e6;
  }
  return usd;
}

/// استدعاء Claude Messages API مباشرة (لا توجد مكتبة Dart رسمية).
class FishIdAi {
  FishIdAi({
    required this.key,
    required this.speciesList,
    this.model = 'claude-opus-5-5',
    this.effort = 'low',
    this.prompt = 'v1',
    this.refs,
    this.refsBelow = 80,
    this.fast = false,
  });

  final String key;
  final String model;
  final String effort;

  /// الوضع السريع لـ Opus: نفس النموذج بسرعة إخراج أعلى وبضعف السعر (Claude API بس).
  final bool fast;

  /// نسخة التعليمات: v1 الحالية، و v2 تجبر النموذج يحدد العائلة والجنس أولًا ويقارن الأنواع المتشابهة بعلاماتها.
  /// نقارن بينها بأداة القياس (bin/eval.dart) على نفس الصور قبل ما نغيّر الافتراضي.
  final String prompt;

  /// مكتبة الصور المرجعية للمرحلة الثانية (اختيارية). تشتغل إذا ثقة أول مرشح أقل من [refsBelow].
  final RefLibrary? refs;
  final int refsBelow;

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
    if (fast) 'speed': 'fast',
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
          // اللغة في رسالة المستخدم مو في التعليمات، عشان تبقى التعليمات المحفوظة مؤقتًا نفسها للغتين.
          if (Zone.current[langKey] == 'en')
            {'type': 'text', 'text': photos.length == 1 ? 'Analyze this photo. Write every text field in clear English.' : 'Analyze these photos of the same fish. Write every text field in clear English.'}
          else
            {'type': 'text', 'text': photos.length == 1 ? 'حلّل هذه الصورة.' : 'حلّل هذه الصور، وكلها لنفس السمكة.'},
        ],
      },
    ],
  };

  /// يرجّع نتيجة التحليل كنص JSON بالشكل المعرّف في [schema]، مع الدرجة والتصنيف المحسوبة من نقاط QIM.
  /// إذا فيه مكتبة صور مرجعية والثقة منخفضة، نعيد ترتيب الأنواع بمقارنة صورة السمكة بصور الأنواع المتشابهة.
  Future<String> identify(List<Photo> photos) async {
    final result = await _call(requestBody(photos));
    if (result['freshness'] case final Map<String, dynamic> f) completeFreshness(f);
    await _compareWithRefs(photos, result);
    return jsonEncode(result);
  }

  /// صورة الصندوق للدلّال: صورة (حتى 3) لصندوق أو كوم سمك في الحراج، ويرجّع الأنواع بأسمائها المحلية وعدد تقريبي وطزاجة تقريبية.
  /// النتيجة نص JSON بالشكل المعرّف في [boxSchema].
  Future<String> box(List<Photo> photos) async {
    final en = Zone.current[langKey] == 'en';
    final result = await _call({
      'model': model,
      if (fast) 'speed': 'fast',
      'max_tokens': 5000,
      'output_config': {
        'effort': effort,
        'format': {'type': 'json_schema', 'schema': boxSchema},
      },
      'fallbacks': 'default',
      'system': [
        {
          'type': 'text',
          'text': _boxSystem,
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
            {
              'type': 'text',
              'text': en
                  ? 'These photos show the same box or load. List the fish in it. Write every text field in clear English.'
                  : (photos.length == 1 ? 'وش الأسماك اللي في هذا الصندوق؟' : 'هذه الصور لنفس الصندوق أو الحمولة. وش الأسماك اللي فيها؟'),
            },
          ],
        },
      ],
    });
    return jsonEncode(tidyBox(result));
  }

  /// يرتّب الأنواع من الأكثر عددًا، ويحسب المجموع من الأنواع نفسها عشان يطابق الكشف.
  static Map<String, dynamic> tidyBox(Map<String, dynamic> result) {
    final items = [
      for (final i in (result['items'] as List? ?? const []).whereType<Map>())
        if (((i['count'] as num?) ?? 0) > 0) i.cast<String, dynamic>(),
    ]..sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    for (final i in items) {
      final id = '${i['id'] ?? ''}';
      i['id'] = RegExp(r'^[0-9]{1,4}$').hasMatch(id) ? id.padLeft(4, '0') : '';
    }
    result['items'] = items;
    result['total_count'] = items.fold<int>(0, (t, i) => t + ((i['count'] as num?)?.toInt() ?? 0));
    return result;
  }

  String get _boxSystem =>
      '''You help fish auctioneers (dallal) at Saudi fish markets (Red Sea and Arabian Gulf).
You receive 1 to 3 phone photos of ONE box, crate, tray or pile of fish arriving at the auction (haraj).
For every species you can see, give one item:
- id: the species id from the KSAFish list below (format: id|scientific name|English name|Saudi local names). Use an empty string when the fish is not in the list, and put your best guess in name.
- name: the Saudi local market name (from the list when possible).
- count: your best estimate of how many fish of this species are in the box, counting fish you can see or clearly infer (heads, tails, layers). count_min and count_max give an honest range.
- size: small, medium or large for this species.
- freshness: 0 to 100 visual freshness estimate from eyes, gill colour if visible, skin shine and slime (100 = just caught). Use -1 when you cannot judge.
- confidence: 0 to 100 for the species id.
- note: one short note (for example "some fish hidden under ice").
Also give overall_freshness (0 to 100, or -1), a one-sentence summary for the auctioneer, and photo_tip (how to photograph better, or an empty string).
Set is_fish_load to false and items to [] when the photos do not show fish.
Be honest: counts in a deep box are estimates, keep ranges wide when layers are hidden, and keep confidence low for look-alike species.
Write every text field in clear Modern Standard Arabic that Saudi users understand, unless the user asks for English.

KSAFish list:
$speciesList''';

  static final boxSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['is_fish_load', 'items', 'overall_freshness', 'summary', 'photo_tip'],
    'properties': {
      'is_fish_load': {'type': 'boolean'},
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['id', 'name', 'count', 'count_min', 'count_max', 'size', 'freshness', 'confidence', 'note'],
          'properties': {
            'id': {'type': 'string'},
            'name': {'type': 'string'},
            'count': {'type': 'integer'},
            'count_min': {'type': 'integer'},
            'count_max': {'type': 'integer'},
            'size': {
              'type': 'string',
              'enum': ['small', 'medium', 'large'],
            },
            'freshness': {'type': 'integer'},
            'confidence': {'type': 'integer'},
            'note': {'type': 'string'},
          },
        },
      },
      'overall_freshness': {'type': 'integer'},
      'summary': {'type': 'string'},
      'photo_tip': {'type': 'string'},
    },
  };

  Future<void> _compareWithRefs(List<Photo> photos, Map<String, dynamic> result) async {
    final lib = refs;
    final cands = (result['candidates'] as List? ?? const []).cast<Map>();
    if (lib == null || cands.isEmpty) return;
    final top = (cands.first['confidence'] as num?)?.toInt() ?? 0;
    if (top >= refsBelow) return;
    final pool = lib.poolFor([for (final c in cands) '${c['id']}'.padLeft(4, '0')]);
    if (pool.length < 2) return;
    try {
      final second = await _call({
        'model': model,
        if (fast) 'speed': 'fast',
        'max_tokens': 3000,
        'output_config': {
          'effort': effort,
          'format': {'type': 'json_schema', 'schema': refsSchema},
        },
        'fallbacks': 'default',
        'system': refsSystem,
        'messages': [
          {'role': 'user', 'content': await refsContent(lib, photos, pool)},
        ],
      });
      final ranked = [
        for (final c in (second['candidates'] as List? ?? const []).cast<Map>())
          if (pool.contains('${c['id']}'.padLeft(4, '0'))) {...c, 'id': '${c['id']}'.padLeft(4, '0')},
      ];
      if (ranked.isEmpty) return;
      result['candidates'] = ranked;
      result['refs_compared'] = pool;
    } on FishIdError catch (e) {
      // المرحلة الثانية تحسين، فإذا فشلت نرجع نتيجة المرحلة الأولى كما هي.
      stderr.writeln('FishId: refs stage skipped: ${e.code}');
    }
  }

  Future<Map<String, dynamic>> _call(Map<String, Object> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(_url));
      req.headers
        ..set('x-api-key', key)
        ..set('anthropic-version', '2026-10-21')
        ..set('anthropic-beta', fast ? 'server-side-fallback-2026-07-01,fast-mode-2026-02-01' : 'server-side-fallback-2026-07-01')
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 90));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429 || res.statusCode == 529) throw const FishIdError('busy', 'الخدمة مشغولة، حاول بعد شوي', status: 503);
      if (res.statusCode >= 300) {
        stderr.writeln('FishId: Claude ${res.statusCode}: $text');
        // الرصيد خلص أو المفتاح موقوف: نرمز لها برمز خاص عشان تطلع تنبيه في لوحة الأدمن.
        if (res.statusCode == 400 && text.contains('credit balance')) {
          throw const FishIdError('claude_credit', 'الخدمة متوقفة مؤقتًا، حاول بعد شوي', status: 503);
        }
        if (res.statusCode == 401 || res.statusCode == 403) throw const FishIdError('claude_account', 'الخدمة متوقفة مؤقتًا، حاول بعد شوي', status: 503);
        throw const FishIdError('fishid_error', 'تعذّر تحليل الصورة، حاول مرة ثانية', status: 502);
      }
      final msg = jsonDecode(text) as Map<String, dynamic>;
      stdout.writeln('FishId: ${msg['model']} usage ${jsonEncode(msg['usage'])}');
      if (Zone.current[usageKey] case final List<Map<String, dynamic>> log when msg['usage'] is Map) {
        log.add({'model': msg['model'] ?? model, ...(msg['usage'] as Map).cast<String, dynamic>()});
      }
      if (msg['stop_reason'] == 'refusal') throw const FishIdError('fishid_refused', 'ما قدرنا نحلل هذه الصورة، جرّب صورة ثانية');
      if (msg['stop_reason'] == 'max_tokens') throw const FishIdError('fishid_error', 'تعذّر تحليل الصورة، حاول مرة ثانية', status: 502);
      final out = (msg['content'] as List).where((b) => b['type'] == 'text').map((b) => b['text'] as String).join();
      return jsonDecode(out) as Map<String, dynamic>;
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
