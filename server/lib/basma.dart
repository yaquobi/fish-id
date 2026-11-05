import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'claude.dart';

/// يرسل صورة لخدمة بصمة ويرجّع أقرب الأنواع: [{"id": "0365", "score": 0.31}, ...] و ms.
typedef BasmaRank = Future<Map<String, dynamic>> Function(Photo photo);

/// «بصمة» في الظل: بعد كل فحص ناجح بـ Opus نرسل نفس الصورة لنموذجنا (bench/bioclip/serve.py)
/// ونسجّل جواب الاثنين في basma-shadow.jsonl. المستخدم ما يشوف شي، والفحص ما يتأخر.
/// الهدف نعرف دقة بصمة على صور حقيقية من السوق قبل ما نخليها تجاوب بنفسها.
/// ما نسجّل رقم الحساب ولا الصورة، بس أرقام الأنواع.
class BasmaShadow {
  BasmaShadow(this.file, this.rank);

  /// [url] مثل http://basma:8090/basma (FISHID_BASMA_URL).
  factory BasmaShadow.http(String dir, Uri url) {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    return BasmaShadow(File('$dir/basma-shadow.jsonl'), (photo) async {
      final req = await http.postUrl(url);
      req.headers.contentType = ContentType.parse(photo.mediaType);
      // خدمة بصمة (Python) تقرا الطول من content-length، والإرسال المقطّع يوصلها فاضي.
      req.contentLength = photo.bytes.length;
      req.add(photo.bytes);
      // أول طلب بعد فترة هدوء يطوّل (النموذج يرجع للذاكرة)، والمقارنة بالخلفية فما يضر ننتظر.
      final res = await req.close().timeout(const Duration(seconds: 90));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('basma ${res.statusCode}');
      return jsonDecode(body) as Map<String, dynamic>;
    });
  }

  final File file;
  final BasmaRank rank;
  Future<void> _queue = Future.value();
  int _pending = 0;

  /// يقارن بالخلفية. [result] جواب Opus كما رجع للتطبيق.
  void compare(Photo photo, String result, DateTime now) {
    // إذا الخدمة بطيئة ما نكدّس الصور في الذاكرة.
    if (_pending >= 5) return;
    _pending++;
    _queue = _queue.then((_) => _one(photo, result, now)).whenComplete(() => _pending--);
  }

  Future<void> _one(Photo photo, String result, DateTime now) async {
    final List<String> opus;
    try {
      final r = jsonDecode(result) as Map<String, dynamic>;
      if (r['is_fish'] == false) return;
      opus = [for (final c in (r['candidates'] as List? ?? const []).cast<Map>()) '${c['id']}'.padLeft(4, '0')];
    } on Object {
      return;
    }
    if (opus.isEmpty) return;
    try {
      final b = await rank(photo);
      final top = [for (final t in (b['top'] as List).cast<Map>()) '${t['id']}'.padLeft(4, '0')];
      final score = ((b['top'] as List).first as Map)['score'];
      await file.writeAsString(
        '${jsonEncode({'t': now.toUtc().toIso8601String(), 'opus': opus, 'basma': top, 'score': score, 'ms': b['ms']})}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (e) {
      stderr.writeln('basma: $e');
    }
  }

  /// للوحة الأدمن: كم مرة اتفقت بصمة مع Opus، والسرعة، وآخر 20 فحص.
  Map<String, dynamic> summary() {
    final rows = <Map<String, dynamic>>[];
    if (file.existsSync()) {
      for (final l in file.readAsLinesSync()) {
        if (l.trim().isEmpty) continue;
        try {
          rows.add(jsonDecode(l) as Map<String, dynamic>);
        } on Object {
          // سطر ناقص
        }
      }
    }
    var same = 0, inOpus = 0, inBasma = 0, ms = 0;
    for (final r in rows) {
      final o = (r['opus'] as List).cast<String>(), b = (r['basma'] as List).cast<String>();
      if (o.first == b.first) same++;
      if (o.contains(b.first)) inOpus++;
      if (b.take(3).contains(o.first)) inBasma++;
      ms += (r['ms'] as num? ?? 0).toInt();
    }
    final n = rows.length;
    double pct(int x) => n == 0 ? 0 : (1000 * x / n).round() / 10;
    return {
      'scans': n,
      'same_top1': pct(same),
      'basma_top1_in_opus': pct(inOpus),
      'opus_top1_in_basma_top3': pct(inBasma),
      'avg_ms': n == 0 ? 0 : ms ~/ n,
      'last': rows.reversed.take(20).toList(),
    };
  }
}
