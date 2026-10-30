import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'claude.dart';

/// قائمة «بلّغني بالإطلاق» من صفحة hawat.id: إيميل أو جوال سعودي، بموافقة صريحة، عشان نرسل لهم رسالة وقت التدشين.
/// الملف `waitlist.json` في مجلد الحسابات. ما نحفظ IP، والتسجيل نفسه ينحذف من الأدمن إذا طلب صاحبه.
class Waitlist {
  Waitlist._(this.dir, this._items);

  final String dir;
  final List<Map<String, dynamic>> _items;

  static const _max = 50000;
  static const _perIpDay = 5;
  static final _email = RegExp(r'^[^\s@<>"]{1,64}@[a-z0-9.-]{1,190}\.[a-z]{2,24}$');

  /// كم تسجيل من كل IP اليوم، في الذاكرة بس (بصمة رقمية مو الـ IP نفسه).
  String _today = '';
  final _perIp = <int, int>{};

  static Waitlist open(String dir) {
    final f = File('$dir/waitlist.json');
    final list = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as List).map((e) => (e as Map).cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];
    return Waitlist._(dir, list);
  }

  int get count => _items.length;

  /// يحوّل المدخل لإيميل بحروف صغيرة أو جوال سعودي بصيغة +9665xxxxxxxx، أو null إذا ما يصلح.
  static ({String kind, String value})? normalize(String raw) {
    const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
    var s = raw.trim();
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
    }
    if (s.contains('@')) {
      final e = s.toLowerCase();
      return _email.hasMatch(e) && !e.contains('..') ? (kind: 'email', value: e) : null;
    }
    var d = s.replaceAll(RegExp(r'[\s\-().]'), '');
    if (d.startsWith('+')) d = d.substring(1);
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('966')) d = d.substring(3);
    if (d.startsWith('0')) d = d.substring(1);
    return RegExp(r'^5\d{8}$').hasMatch(d) ? (kind: 'phone', value: '+966$d') : null;
  }

  /// يضيف التسجيل ويرجّع true إذا جديد، و false إذا كان مسجّل من قبل.
  Future<bool> add(Map body, {required String ip, required DateTime now}) async {
    if (body['consent'] != true) throw const FishIdError('bad_request', 'لازم توافق إننا نراسلك وقت الإطلاق');
    final c = normalize('${body['contact'] ?? ''}');
    if (c == null) throw const FishIdError('bad_request', 'اكتب إيميل صحيح أو رقم جوال سعودي (05xxxxxxxx)');
    if (_items.any((e) => e['contact'] == c.value)) return false;
    final day = now.toUtc().toIso8601String().substring(0, 10);
    if (day != _today) {
      _today = day;
      _perIp.clear();
    }
    final who = ip.hashCode;
    if ((_perIp[who] ?? 0) >= _perIpDay || _items.length >= _max) throw const FishIdError('busy', 'سجلت كثير اليوم، جرب بكره', status: 429);
    _perIp[who] = (_perIp[who] ?? 0) + 1;
    String clip(Object? v, int n) {
      final t = '${v ?? ''}'.trim();
      return t.length > n ? t.substring(0, n) : t;
    }

    final rnd = Random.secure();
    _items.add({
      'id': List.generate(6, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join(),
      'contact': c.value,
      'kind': c.kind,
      'name': clip(body['name'], 60),
      'lang': body['lang'] == 'en' ? 'en' : 'ar',
      'src': clip(body['src'], 40),
      'at': now.toUtc().toIso8601String(),
    });
    await save();
    return true;
  }

  /// للوحة الأدمن: العدد (الكل، اليوم بتوقيت السعودية، آخر 7 أيام) والقائمة، الأحدث أول.
  Map<String, dynamic> view(DateTime now) {
    String day(DateTime t) => t.toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 10);
    final today = day(now), week = day(now.subtract(const Duration(days: 6)));
    var t = 0, w = 0, emails = 0;
    for (final e in _items) {
      final d = day(DateTime.parse('${e['at']}'));
      if (d == today) t++;
      if (d.compareTo(week) >= 0) w++;
      if (e['kind'] == 'email') emails++;
    }
    return {'count': _items.length, 'today': t, 'week': w, 'emails': emails, 'phones': _items.length - emails, 'items': _items.reversed.toList()};
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e['id'] == id);
    await save();
  }

  Future<void> _queue = Future.value();

  Future<void> save() {
    final text = jsonEncode(_items);
    return _queue = _queue.then((_) async {
      final tmp = File('$dir/waitlist.json.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('$dir/waitlist.json');
    });
  }
}
