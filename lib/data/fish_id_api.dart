import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import 'box.dart';
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

/// ما فيه نت أو الخادم مشغول مؤقتًا: الطلب ممكن ينجح لو أعدناه بعدين.
class FishIdOfflineException extends FishIdException {
  const FishIdOfflineException(super.message);
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

  /// لصاحب باقة المحلات: رمز المحل وعدد الجوالات والرصيد المشترك ({code, devices, maxDevices, used, cap})، وإلا null.
  static final shop = ValueNotifier<Map<String, dynamic>?>(null);

  /// للمفتش الرسمي: اسمه وجهته ورمزه وعدد زياراته ({name, agency, code, active, today, month...})، وإلا null.
  static final gov = ValueNotifier<Map<String, dynamic>?>(null);

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
    'x-fishid-lang': L10n.lang.value,
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
      final body = jsonDecode(res.body) as Map;
      final n = body['remaining'];
      if (res.statusCode == 200 && n is int) remaining.value = n;
      if (res.statusCode == 200) {
        shop.value = body['shop'] is Map ? (body['shop'] as Map).cast<String, dynamic>() : null;
        gov.value = body['gov'] is Map ? (body['gov'] as Map).cast<String, dynamic>() : null;
      }
    } on Object {
      return;
    }
  }

  /// بعد الشراء: يطلب من الخادم يتأكد من الاشتراك عند RevenueCat ويحدّث المتبقي.
  static Future<void> sync() async {
    if (isDemo) return;
    try {
      final base = apiUrl.endsWith('/') ? apiUrl : '$apiUrl/';
      final res = await http
          .post(Uri.parse('${base}fishId/sync'), headers: await _headers())
          .timeout(const Duration(seconds: 20));
      _readRemaining(res);
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
      throw FishIdException(_offline);
    }
    final body = utf8.decode(res.bodyBytes);
    _readRemaining(res);
    if (res.statusCode == 402) {
      remaining.value = 0;
      throw FishIdQuotaException(
        _serverMessage(body) ??
            tr(
              'خلصت فحوصاتك المجانية. اشترك عشان تكمل الفحص.',
              'You have used your free scans. Subscribe to keep scanning.',
            ),
      );
    }
    if (res.statusCode != 200) {
      throw FishIdException(
        _serverMessage(body) ??
            tr('تعذّر تحليل الصورة، حاول مرة ثانية.', 'Could not analyze the photo. Please try again.'),
      );
    }
    try {
      // الخادم يرجّع نصًا، وهذا النص نفسه JSON للنتيجة.
      final text = jsonDecode(body) as String;
      return FishResult.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      throw FishIdException(
        tr('وصل رد غير متوقع من الخادم، حاول مرة ثانية.', 'The server sent an unexpected reply. Please try again.'),
      );
    }
  }

  /// صورة الصندوق للدلّال: الأنواع وعددها التقريبي وطزاجتها. تنحسب فحص واحد.
  static Future<BoxResult> box(List<Uint8List> images) async {
    if (isDemo) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return BoxResult.demo;
    }
    final res = await _post('fishId/box', {
      'images': [
        for (final image in images) {'image': base64Encode(image), 'mediaType': mediaTypeOf(image)},
      ],
    }, timeout: 120);
    if (res.statusCode == 402) {
      remaining.value = 0;
      throw FishIdQuotaException(
        _serverMessage(utf8.decode(res.bodyBytes)) ??
            tr('خلصت فحوصاتك. اشترك عشان تكمل.', 'You have used your scans. Subscribe to keep scanning.'),
      );
    }
    final body = _body(res, tr('تعذّر تحليل الصورة، حاول مرة ثانية.', 'Could not analyze the photo. Please try again.'));
    try {
      return BoxResult.fromJson(jsonDecode(body as String) as Map<String, dynamic>);
    } on Object {
      throw FishIdException(
        tr('وصل رد غير متوقع من الخادم، حاول مرة ثانية.', 'The server sent an unexpected reply. Please try again.'),
      );
    }
  }

  /// دخول المفتش برمز الجهة (GOV-XXXXXX). يرجّع بياناته ويحدّث [gov].
  static Future<Map<String, dynamic>> govJoin(String code) async {
    if (isDemo) {
      gov.value = demoInspector;
      remaining.value = 9999;
      return demoInspector;
    }
    final res = await _post('fishId/gov/join', {'code': code.trim()});
    final p = (_body(res, tr('رمز المفتش غير صحيح', 'This inspector code is not valid')) as Map).cast<String, dynamic>();
    gov.value = p;
    return p;
  }

  /// خروج المفتش من الوضع الرسمي على هذا الجوال.
  static Future<void> govLeave() async {
    if (!isDemo) _body(await _post('fishId/gov/leave', const {}), tr('تعذّر الخروج، حاول مرة ثانية', 'Could not sign out. Try again.'));
    gov.value = null;
    await refreshRemaining();
  }

  /// آخر زيارات المفتش.
  static Future<List<Map<String, dynamic>>> govVisits() async {
    if (isDemo) return const [];
    final http.Response res;
    try {
      res = await http.get(Uri.parse('${_base}fishId/gov/visits'), headers: await _headers()).timeout(const Duration(seconds: 20));
    } on Exception {
      throw FishIdException(_offline);
    }
    final b = (_body(res, tr('تعذّر جلب الزيارات', 'Could not load visits')) as Map).cast<String, dynamic>();
    if (b['profile'] is Map) gov.value = (b['profile'] as Map).cast<String, dynamic>();
    return [for (final v in (b['visits'] as List? ?? const [])) (v as Map).cast<String, dynamic>()];
  }

  /// يحفظ الزيارة التفتيشية على الخادم مع صورها، ويرجّعها برقمها المرجعي.
  static Future<Map<String, dynamic>> govVisit(Map<String, dynamic> visit, List<Uint8List> images) async {
    if (isDemo) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return {...visit, 'ref': 'INS-2026-00001', 'at': DateTime.now().toUtc().toIso8601String(), 'inspectorName': gov.value?['name'] ?? ''};
    }
    final res = await _post('fishId/gov/visit', {
      ...visit,
      'images': [
        for (final image in images.take(3)) {'image': base64Encode(image), 'mediaType': mediaTypeOf(image)},
      ],
    }, timeout: 90);
    return (_body(res, tr('تعذّر حفظ الزيارة، حاول مرة ثانية', 'Could not save the visit. Try again.')) as Map).cast<String, dynamic>();
  }

  static const demoInspector = <String, dynamic>{
    'id': 'in_demo',
    'name': 'مفتش تجريبي',
    'branch': 'جدة',
    'code': 'GOV-DEMO00',
    'agency': 'وزارة البيئة والمياه والزراعة',
    'until': '2027-12-31T23:59:00.000Z',
    'active': true,
    'month': 0,
    'today': 0,
  };

  static String get _base => apiUrl.endsWith('/') ? apiUrl : '$apiUrl/';

  static Future<http.Response> _post(String path, Object body, {int timeout = 20}) async {
    try {
      final res = await http
          .post(Uri.parse('$_base$path'), headers: await _headers(), body: jsonEncode(body))
          .timeout(Duration(seconds: timeout));
      _readRemaining(res);
      return res;
    } on Exception {
      throw FishIdException(_offline);
    }
  }

  /// جسم الرد إذا نجح، وإلا يرمي رسالة الخادم أو [fallback].
  static Object? _body(http.Response res, String fallback) {
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw FishIdException(_serverMessage(text) ?? fallback);
    try {
      return jsonDecode(text);
    } on FormatException {
      throw FishIdException(fallback);
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
    String? takenAt,
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
              'takenAt': ?takenAt,
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw FishIdOfflineException(_offline);
    }
    if (res.statusCode == 429 || res.statusCode >= 500) throw FishIdOfflineException(_offline);
    if (res.statusCode != 200) {
      throw FishIdException(
        _serverMessage(utf8.decode(res.bodyBytes)) ??
            tr('تعذّر حفظ المساهمة، حاول مرة ثانية.', 'Could not save your contribution. Please try again.'),
      );
    }
  }

  /// يضيف فحوصات رمز الهدية للحساب ويرجّع رسالة الخطأ إذا الرمز ما ينفع.
  static Future<void> redeem(String code) async {
    if (isDemo) return;
    final base = apiUrl.endsWith('/') ? apiUrl : '$apiUrl/';
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('${base}fishId/redeem'), headers: await _headers(), body: jsonEncode({'code': code}))
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw FishIdException(_offline);
    }
    _readRemaining(res);
    if (res.statusCode != 200) {
      throw FishIdException(
        _serverMessage(utf8.decode(res.bodyBytes)) ?? tr('الرمز غير صحيح', 'This code is not valid'),
      );
    }
  }

  static String get _offline => tr(
    'تعذّر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة ثانية.',
    'Could not reach the server. Check your internet and try again.',
  );

  /// رسائل الخادم عربية، فبالإنجليزي نترجم أشهرها برمزها ونرجع null للباقي عشان تنعرض الرسالة العامة.
  static const _enMessages = {
    'quota': 'You have used your scans. Subscribe to keep scanning.',
    'blocked': 'This account is suspended. Please contact us.',
    'update_app': 'Please update the app from the store to keep scanning.',
    'busy': 'The service is busy. Please try again in a minute.',
    'fishid_type': 'This image type is not supported. Use JPG or PNG.',
    'fishid_size': 'The photo is too large. Make it smaller and try again.',
    'fishid_count': 'Send 1 to 3 photos of the same fish.',
    'fishid_empty': 'The photo is empty.',
    'fishid_off': 'Fish identification is not available right now.',
    'bad_code': 'This code is not valid.',
    'code_used': 'You have already used this code.',
    'code_full': 'This code has run out.',
    'shop_taken': 'This phone is already linked to another shop.',
    'shop_full': 'This shop has reached its phone limit.',
    'gov_stopped': 'This inspector code is stopped. Ask your supervisor.',
    'gov_expired': 'The agency subscription has ended or is stopped.',
    'gov_devices': 'This code is already used on two phones. Ask your supervisor for a new code.',
    'gov_none': 'Sign in as an inspector first.',
  };

  /// رسالة الخطأ من رد الخادم بلغة التطبيق، إن وجدت.
  static String? _serverMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final data = j['data'] is Map ? j['data'] as Map : j;
        if (L10n.en) return _enMessages[data['code']];
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
