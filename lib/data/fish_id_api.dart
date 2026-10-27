import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'result.dart';

/// عنوان خادم حوات. يتغير وقت البناء: --dart-define=API_URL=http://localhost:8080/
/// والقيمة DEMO تشغّل وضع التجربة بنتيجة ثابتة بدون خادم.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://hawat.id/api/');
bool get isDemo => apiUrl == 'DEMO';

class FishIdException implements Exception {
  const FishIdException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// يرسل الصورة لخادم FISH ID (مجلد server/) على https://hawat.id/api/.
/// مفتاح Claude موجود في الخادم فقط، والتطبيق ما يعرفه.
abstract final class FishIdApi {
  static Future<FishResult> identify(Uint8List image) async {
    if (isDemo) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return FishResult.demo;
    }
    final base = apiUrl.endsWith('/') ? apiUrl : '$apiUrl/';
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${base}fishId/identify'),
            headers: {'content-type': 'application/json; charset=utf-8'},
            // هكذا يرمّز Serverpod نوع ByteData.
            body: jsonEncode({'image': "decode('${base64Encode(image)}', 'base64')", 'mediaType': mediaTypeOf(image)}),
          )
          .timeout(const Duration(seconds: 100));
    } on Exception {
      throw const FishIdException('تعذّر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة ثانية.');
    }
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw FishIdException(_serverMessage(body) ?? 'تعذّر تحليل الصورة، حاول مرة ثانية.');
    try {
      // الخادم يرجّع نصًا، وهذا النص نفسه JSON للنتيجة.
      final text = jsonDecode(body) as String;
      return FishResult.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      throw const FishIdException('وصل رد غير متوقع من الخادم، حاول مرة ثانية.');
    }
  }

  /// رسالة HawatException العربية من رد الخطأ، إن وجدت.
  static String? _serverMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final data = j['data'] is Map ? j['data'] as Map : j;
        final m = data['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// نوع الصورة من أول بايتات الملف.
  static String mediaTypeOf(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length > 11 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }
}
