import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'claude.dart';

typedef Identify = Future<String> Function(List<Photo> photos);

/// مسارات الخادم. نفس بروتوكول Serverpod اللي يكلمه التطبيق:
/// POST fishId/identify بجسم `{"image": "decode('BASE64', 'base64')", "mediaType": "image/jpeg"}`،
/// أو `{"images": [{"image": ..., "mediaType": ...}, ...]}` حتى [maxPhotos] صور لنفس السمكة.
/// والرد نص JSON داخل سلسلة JSON. الخطأ 4xx/5xx بجسم {"code", "message"}.
class FishIdApp {
  FishIdApp({required this.identify, this.perMinute = 30, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Identify? identify;
  final int perMinute;
  final DateTime Function() _clock;

  static const maxBytes = 5 * 1024 * 1024;
  static const maxPhotos = 3;
  static const types = {'image/jpeg', 'image/png', 'image/webp'};
  static const _cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'POST, GET, OPTIONS',
    'access-control-allow-headers': 'content-type',
  };

  int _minute = 0;
  int _count = 0;

  Handler get handler => (Request req) async {
    if (req.method == 'OPTIONS') return Response.ok(null, headers: _cors);
    // يقبل المسار مع /api/ أو بدونها، حسب إعداد البروكسي.
    final path = req.url.path.replaceFirst(RegExp(r'^api/'), '');
    if (req.method == 'GET' && (path == '' || path == 'health')) {
      return _json(200, {'ok': true, 'service': 'fish-id', 'ready': identify != null});
    }
    if (req.method == 'POST' && path == 'fishId/identify') {
      try {
        return _json(200, await _identify(req));
      } on FishIdError catch (e) {
        return _json(e.status, {'code': e.code, 'message': e.message});
      }
    }
    return _json(404, {'code': 'not_found', 'message': 'المسار غير موجود'});
  };

  Future<String> _identify(Request req) async {
    final run = identify;
    if (run == null) throw const FishIdError('fishid_off', 'خدمة التعرف على الأسماك غير مفعّلة حاليًا', status: 503);
    final Map<String, dynamic> body;
    try {
      // base64 يكبّر الحجم الثلث، فالحد هنا أكبر من حد الصورة.
      final raw = await req.read().fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) {
        if (b.length + chunk.length > maxBytes * maxPhotos * 1.4) throw const FishIdError('fishid_size', 'الصورة كبيرة، صغّرها وحاول مرة ثانية', status: 413);
        return b..add(chunk);
      });
      body = jsonDecode(utf8.decode(raw.takeBytes())) as Map<String, dynamic>;
    } on FishIdError {
      rethrow;
    } on Object {
      throw const FishIdError('bad_request', 'الطلب غير صالح');
    }
    final list = body['images'] is List ? body['images'] as List : [body];
    if (list.isEmpty || list.length > maxPhotos) throw const FishIdError('fishid_count', 'أرسل من صورة إلى 3 صور لنفس السمكة');
    final photos = [for (final item in list) _photo(item)];

    final now = _clock().millisecondsSinceEpoch ~/ 60000;
    if (now != _minute) {
      _minute = now;
      _count = 0;
    }
    if (++_count > perMinute) throw const FishIdError('busy', 'الخدمة مشغولة، حاول بعد دقيقة', status: 429);

    return run(photos);
  }

  static Photo _photo(Object? item) {
    if (item is! Map) throw const FishIdError('bad_request', 'الطلب غير صالح');
    final mediaType = item['mediaType'];
    if (mediaType is! String || !types.contains(mediaType)) throw const FishIdError('fishid_type', 'نوع الصورة غير مدعوم، استخدم JPG أو PNG');
    final image = _decodeImage(item['image']);
    if (image == null || image.isEmpty) throw const FishIdError('fishid_empty', 'الصورة فاضية');
    if (image.length > maxBytes) throw const FishIdError('fishid_size', 'الصورة كبيرة، صغّرها وحاول مرة ثانية', status: 413);
    return Photo(image, mediaType);
  }

  /// يقبل ترميز Serverpod لـ ByteData، أو base64 عادي.
  static Uint8List? _decodeImage(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r"^decode\('(.*)', 'base64'\)$", dotAll: true).firstMatch(v);
    try {
      return base64Decode(m?.group(1) ?? v);
    } on FormatException {
      return null;
    }
  }

  static Response _json(int status, Object body) =>
      Response(status, body: jsonEncode(body), headers: {..._cors, 'content-type': 'application/json; charset=utf-8'});
}
