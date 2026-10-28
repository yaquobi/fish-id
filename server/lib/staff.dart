import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'claude.dart';

/// مستخدمين لوحة الأدمن غير المالك، كل واحد برمز دخول خاص وصلاحية:
/// admin كل شيء إلا إدارة المستخدمين، accountant المحاسبة والتقارير والتنبيهات، investor التقارير بس.
/// الملف `staff.json` في مجلد الحسابات. الرمز ينعرض مرة وحدة وقت الإضافة.
class StaffStore {
  StaffStore._(this.dir, this._staff);

  final String dir;
  final Map<String, Map<String, dynamic>> _staff;

  static const roles = {'admin', 'accountant', 'investor'};

  static StaffStore open(String dir) {
    final f = File('$dir/staff.json');
    final m = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())) : <String, Map<String, dynamic>>{};
    return StaffStore._(dir, m);
  }

  /// صاحب الرمز، أو null. نقارن مع كل الرموز بوقت ثابت.
  Map<String, dynamic>? match(String token) {
    Map<String, dynamic>? found;
    for (final e in _staff.entries) {
      final t = '${e.value['token']}';
      var d = t.length ^ token.length;
      for (var i = 0; i < t.length; i++) {
        d |= t.codeUnitAt(i) ^ (i < token.length ? token.codeUnitAt(i) : 0);
      }
      if (d == 0) found = {'id': e.key, ...e.value};
    }
    return found;
  }

  List<Map<String, dynamic>> list() => [
    for (final e in _staff.entries) {'id': e.key, 'name': e.value['name'], 'role': e.value['role'], 'created': e.value['created']},
  ];

  /// يضيف مستخدمًا ويرجّع رمزه (المرة الوحيدة اللي ينعرض فيها).
  Future<Map<String, dynamic>> add(String name, String role, DateTime now) async {
    name = name.trim();
    if (name.isEmpty || name.length > 60 || !roles.contains(role)) throw const FishIdError('bad_request', 'اكتب الاسم واختر الصلاحية');
    final rnd = Random.secure();
    String hex(int n) => List.generate(n, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final id = hex(6), token = 'fs_${hex(24)}';
    _staff[id] = {'name': name, 'role': role, 'token': token, 'created': now.toUtc().toIso8601String()};
    await _save();
    return {'id': id, 'name': name, 'role': role, 'token': token};
  }

  Future<void> remove(String id) async {
    _staff.remove(id);
    await _save();
  }

  Future<void> _queue = Future.value();

  Future<void> _save() {
    final text = jsonEncode(_staff);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/staff.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/staff.json');
    });
  }
}
