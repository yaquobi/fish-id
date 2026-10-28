import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

/// خلصت الفحوصات (المجانية أو سقف الشهر)، فنعرض الاشتراك بدل «حاول مرة ثانية».
class FishIdQuotaException extends FishIdException {
  const FishIdQuotaException(super.message);
}

/// يرسل الصورة لخادم FISH ID (مجلد server/) على https://hawat.id/api/.
/// مفتاح Claude موجود في الخادم فقط، والتطبيق ما يعرفه.
abstract final class FishIdApi {
  /// الفحوصات المتبقية للحساب كما يقولها الخادم (null قبل أول رد).
  static final remaining = ValueNotifier<int?>(null);

  /// رقم حساب عشوائي ينحفظ في الجوال أول مرة، بدون اسم أو جوال أو إيميل. الخادم يحسب عليه الفحوصات.
  static Future<String> userId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('fishid_user');
    if (id == null) {
      final rnd = Random.secure();
      id = 'u_${List.generate(32, (_) => rnd.nextInt(36).toRadixString(36)).join()}';
      await prefs.setString('fishid_user', id);
    }
    return id;
  }

  static Future<Map<String, String>> _headers() async => {
    'content-type': 'application/json; charset=utf-8',
    'x-fishid-user': await userId(),
  };

  static void _readRemaining(http.Response res) {
    final n = int.tryParse(res.headers['x-fishid-remaining'] ?? '');
    if (n != null) remaining.value = n;
  }

  /// يسأل الخادم كم فحص باقي، للشاشة الرئيسية. الأخطاء تنتجاهل لأنها معلومة إضافية.
  static Future<void> refreshRemaining() async {
    if (isDemo) return;
    try {
      final base = apiUrl.endsWith('/') ? apiUrl : '$apiUrl/';
      final res = await http
          .get(Uri.parse('${base}fishId/me'), headers: await _headers())
          .timeout(const Duration(seconds: 15));
      final n = (jsonDecode(res.body) as Map)['remaining'];
      if (res.statusCode == 200 && n is int) remaining.value = n;
    } on Object {
      return;
    }
  }

  static Future<FishResult> identify(List<Uint8List> images) async {
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
            headers: await _headers(),
            // هكذا يرمّز Serverpod نوع ByteData.
            body: jsonEncode({
              'images': [
                for (final image in images)
                  {'image': "decode('${base64Encode(image)}', 'base64')", 'mediaType': mediaTypeOf(image)},
              ],
            }),
          )
          .timeout(const Duration(seconds: 100));
    } on Exception {
      throw const FishIdException('تعذّر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة ثانية.');
    }
    final body = utf8.decode(res.bodyBytes);
    _readRemaining(res);
    if (res.statusCode == 402) {
      remaining.value = 0;
      throw FishIdQuotaException(_serverMessage(body) ?? 'خلصت فحوصاتك المجانية. اشترك عشان تكمل الفحص.');
    }
    if (res.statusCode != 200) throw FishIdException(_serverMessage(body) ?? 'تعذّر تحليل الصورة، حاول مرة ثانية.');
    try {
      // الخادم يرجّع نصًا، وهذا النص نفسه JSON للنتيجة.
      final text = jsonDecode(body) as String;
      return FishResult.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      throw const FishIdException('وصل رد غير متوقع من الخادم، حاول مرة ثانية.');
    }
  }

  /// يحفظ الصور على الخادم مع النوع المؤكد وكم يوم من الصيد وطريقة الحفظ، بموافقة المستخدم.
  /// تُستخدم لبناء مجموعة بيانات أسماك الخليج والبحر الأحمر ومعايرة الطزاجة.
  static Future<void> contribute(
    List<Uint8List> images, {
    required String species,
    required bool speciesConfirmed,
    required int days,
    required String storage,
    required List<String> predicted,
    required int score,
  }) async {
    if (isDemo) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return;
    }
    final base = apiUrl.endsWith('/') ? apiUrl : '$apiUrl/';
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${base}fishId/contribute'),
            headers: await _headers(),
            body: jsonEncode({
              'images': [
                for (final image in images)
                  {'image': "decode('${base64Encode(image)}', 'base64')", 'mediaType': mediaTypeOf(image)},
              ],
              'species': species,
              'speciesConfirmed': speciesConfirmed,
              'days': days,
              'storage': storage,
              'predicted': predicted,
              'score': score,
              'consent': true,
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw const FishIdException('تعذّر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة ثانية.');
    }
    if (res.statusCode != 200) throw FishIdException(_serverMessage(utf8.decode(res.bodyBytes)) ?? 'تعذّر حفظ المساهمة، حاول مرة ثانية.');
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
