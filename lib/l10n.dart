import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// لغة التطبيق: عربي أو إنجليزي. تتبع لغة الجوال أول مرة، والمستخدم يغيّرها من القائمة وتنحفظ.
abstract final class L10n {
  static final lang = ValueNotifier<String>(_device());

  static bool get en => lang.value == 'en';

  static String _device() => PlatformDispatcher.instance.locale.languageCode == 'ar' ? 'ar' : 'en';

  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString('fishid_lang');
      if (saved == 'ar' || saved == 'en') lang.value = saved!;
    } on Object {
      return;
    }
  }

  static Future<void> set(String code) async {
    lang.value = code;
    try {
      await (await SharedPreferences.getInstance()).setString('fishid_lang', code);
    } on Object {
      return;
    }
  }
}

/// النص حسب لغة التطبيق.
String tr(String ar, String en) => L10n.en ? en : ar;
