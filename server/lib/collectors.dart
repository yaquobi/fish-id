import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'claude.dart';

/// المصوّرين اللي يجمعون صور الأسماك من الأسواق لتدريب نموذجنا الخاص.
/// كل مصوّر له رابط خاص فيه مفتاح ([add])، يفتحه من جواله ويسجل جواله أو إيميله مرة وحدة ([join])، وبعدها يرفع.
/// الملف `collectors.json` في مجلد الحسابات. الصور نفسها تنحفظ مع صور المساهمين ([ContribStore]) وتتراجع من نفس الصفحة.
class CollectorStore {
  CollectorStore._(this.dir, this._all);

  final String dir;
  final Map<String, Map<String, dynamic>> _all;

  static final keyPattern = RegExp(r'^c_[0-9a-f]{24}$');

  /// زوايا التصوير المسموحة، بنفس ترتيب الصفحة.
  static const parts = ['right', 'left', 'tail', 'whole', 'ice'];

  static CollectorStore open(String dir) {
    final f = File('$dir/collectors.json');
    final m = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())) : <String, Map<String, dynamic>>{};
    return CollectorStore._(dir, m);
  }

  /// المصوّر الفعّال صاحب المفتاح، أو null. نقارن مع كل المفاتيح بوقت ثابت.
  Map<String, dynamic>? find(String key) {
    if (!keyPattern.hasMatch(key)) return null;
    Map<String, dynamic>? found;
    for (final e in _all.entries) {
      var d = 0;
      for (var i = 0; i < key.length; i++) {
        d |= e.key.codeUnitAt(i) ^ key.codeUnitAt(i);
      }
      if (d == 0 && e.value['active'] != false) found = e.value;
    }
    return found;
  }

  List<Map<String, dynamic>> list() => [
    for (final e in _all.entries) {'key': e.key, ...e.value},
  ]..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));

  Future<Map<String, dynamic>> add(String name, String city, DateTime now) async {
    name = name.trim();
    city = city.trim();
    if (name.isEmpty || name.length > 60 || city.length > 40) throw const FishIdError('bad_request', 'اكتب اسم المصوّر ومدينته');
    final rnd = Random.secure();
    final key = 'c_${List.generate(12, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    _all[key] = {'name': name, 'city': city, 'contact': '', 'created': now.toUtc().toIso8601String(), 'active': true, 'fish': 0, 'photos': 0, 'last': null};
    await _save();
    return {'key': key, ..._all[key]!};
  }

  static final _email = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,}$');
  static final _phone = RegExp(r'^\+?[0-9]{9,15}$');

  /// أول دخول: جوال أو إيميل المصوّر وموافقته على شروط الصور.
  Future<void> join(String key, String contact, DateTime now) async {
    final c = find(key);
    if (c == null) throw const FishIdError('collector', 'الرابط غير صالح، اطلب رابط جديد', status: 401);
    contact = contact.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (!_email.hasMatch(contact) && !_phone.hasMatch(contact)) throw const FishIdError('bad_request', 'اكتب رقم جوال أو إيميل صحيح');
    c['contact'] = contact;
    c['joined'] = now.toUtc().toIso8601String();
    await _save();
  }

  Future<void> setActive(String key, bool active) async {
    final c = _all[key];
    if (c == null) return;
    c['active'] = active;
    await _save();
  }

  Future<void> counted(String key, int photos, DateTime now) async {
    final c = _all[key];
    if (c == null) return;
    final day = now.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 10);
    if (c['day'] != day) {
      c['day'] = day;
      c['today'] = 0;
    }
    c['today'] = (c['today'] as int? ?? 0) + 1;
    c['fish'] = (c['fish'] as int? ?? 0) + 1;
    c['photos'] = (c['photos'] as int? ?? 0) + photos;
    c['last'] = now.toUtc().toIso8601String();
    await _save();
  }

  /// عدد اليوم بتوقيت السعودية.
  int today(Map<String, dynamic> c, DateTime now) =>
      c['day'] == now.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 10) ? c['today'] as int? ?? 0 : 0;

  Future<void> _queue = Future.value();

  Future<void> _save() {
    final text = jsonEncode(_all);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/collectors.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/collectors.json');
    });
  }
}
