import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'fish_id_api.dart';

/// طابور «ساهم بصورتك» بدون إنترنت: الصياد في البحر يصوّر ويحفظ، والصور تنتظر في الجوال
/// وتنرسل لحالها أول ما يرجع النت (عند فتح التطبيق، وعند الرجوع له، وكل دقيقة وهو مفتوح).
///
/// كل مساهمة في مجلد `pending_contrib/ID/` داخل ملفات التطبيق الخاصة: الصور `1.jpg`... و `meta.json`.
/// ما فيها اسم ولا موقع، والخادم يحذف بيانات EXIF (فيها الموقع) قبل الحفظ زي المساهمة العادية.
abstract final class UploadQueue {
  /// عدد المساهمات اللي تنتظر الإرسال، للشاشة الرئيسية وشاشة المساهمة.
  static final pending = ValueNotifier<int>(0);

  /// للاختبارات: مجلد بديل وطريقة إرسال بديلة.
  @visibleForTesting
  static Directory? debugDir;
  @visibleForTesting
  static Future<void> Function(List<Uint8List> images, Map<String, dynamic> meta) send = _send;

  static final _rnd = Random.secure();
  static Future<void>? _flushing;
  static _Observer? _observer;

  static Future<Directory> _root() async {
    final base = debugDir ?? await getApplicationSupportDirectory();
    final d = Directory('${base.path}/pending_contrib');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// يبدأ المحاولات التلقائية. ينادى مرة وحدة من main.
  static void start() {
    if (_observer != null) return;
    _observer = _Observer();
    WidgetsBinding.instance.addObserver(_observer!);
    Timer.periodic(const Duration(seconds: 60), (_) {
      if (pending.value > 0) unawaited(flush());
    });
    unawaited(flush());
  }

  /// يحفظ المساهمة في الجوال. [meta] نفس حقول FishIdApi.contribute.
  static Future<void> add(List<Uint8List> images, Map<String, dynamic> meta) async {
    final root = await _root();
    final id = '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 30).toRadixString(36)}';
    final tmp = Directory('${root.path}/.$id')..createSync();
    for (final (i, img) in images.indexed) {
      await File('${tmp.path}/${i + 1}.${FishIdApi.mediaTypeOf(img) == 'image/png' ? 'png' : 'jpg'}').writeAsBytes(img);
    }
    await File('${tmp.path}/meta.json')
        .writeAsString(jsonEncode({...meta, 'takenAt': DateTime.now().toUtc().toIso8601String()}));
    // الاسم النهائي بعد ما تكتمل الملفات، عشان ما نرسل مساهمة ناقصة لو انقفل التطبيق في النص.
    tmp.renameSync('${root.path}/$id');
    await _count();
  }

  static Future<List<Directory>> _items() async {
    final root = await _root();
    return root
        .listSync()
        .whereType<Directory>()
        .where((d) => !d.uri.pathSegments.reversed.elementAt(1).startsWith('.'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  static Future<int> _count() async => pending.value = (await _items()).length;

  /// يرسل كل اللي ينتظر، الأقدم أولًا. يوقف عند أول انقطاع ويرجّع كم وحدة انرسلت.
  static Future<int> flush() {
    final running = _flushing;
    if (running != null) return running.then((_) => 0);
    final f = _flush();
    _flushing = f.whenComplete(() => _flushing = null);
    return f;
  }

  static Future<int> _flush() async {
    var sent = 0;
    try {
      for (final dir in await _items()) {
        final Map<String, dynamic> meta;
        final images = <Uint8List>[];
        try {
          meta = jsonDecode(await File('${dir.path}/meta.json').readAsString()) as Map<String, dynamic>;
          final files =
              dir.listSync().whereType<File>().where((f) => RegExp(r'/\d\.(jpg|png)$').hasMatch(f.path)).toList()
                ..sort((a, b) => a.path.compareTo(b.path));
          for (final f in files) {
            images.add(await f.readAsBytes());
          }
        } on Object {
          dir.deleteSync(recursive: true); // ملف تالف ما بينرسل أبد
          continue;
        }
        try {
          await send(images, meta);
        } on FishIdOfflineException {
          break; // ما فيه نت أو الخادم مشغول: نحاول بعدين
        } on FishIdException {
          // الخادم رفضها (مثل نوع صورة غير مدعوم)، فإعادة المحاولة ما تفيد.
        }
        dir.deleteSync(recursive: true);
        sent++;
      }
    } finally {
      await _count();
    }
    return sent;
  }

  static Future<void> _send(List<Uint8List> images, Map<String, dynamic> m) => FishIdApi.contribute(
    images,
    species: '${m['species'] ?? ''}',
    speciesConfirmed: m['speciesConfirmed'] == true,
    days: m['days'] is int ? m['days'] as int : -1,
    storage: '${m['storage'] ?? 'unknown'}',
    predicted: [for (final p in (m['predicted'] as List? ?? const [])) '$p'],
    score: m['score'] is int ? m['score'] as int : -1,
    takenAt: m['takenAt'] as String?,
  );
}

class _Observer with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(UploadQueue.flush());
  }
}
