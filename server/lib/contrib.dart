import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'claude.dart';

/// صور يساهم فيها المستخدمون بموافقتهم: الصورة مع النوع المؤكد وكم يوم من الصيد وطريقة الحفظ.
/// هي أساس أول مجموعة بيانات لأسماك الخليج والبحر الأحمر وطزاجتها، ونستخدمها للمعايرة واختبار الدقة.
///
/// تنحفظ في `dir/YYYY-MM-DD/ID/` (الصور + meta.json)، بدون أي بيانات شخصية، وبعد حذف بيانات EXIF
/// (فيها موقع التصوير ونوع الجوال).
class ContribStore {
  ContribStore(this.dir);
  final String dir;

  static final _rnd = Random.secure();

  /// يرجّع null إذا المجلد غير موجود، فتنطفي المساهمة بهدوء.
  static ContribStore? open(String dir) => Directory(dir).existsSync() ? ContribStore(dir) : null;

  Future<String> save(List<Photo> photos, Map<String, Object?> meta, DateTime now) async {
    final day = now.toUtc().toIso8601String().substring(0, 10);
    final id = '${now.millisecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 30).toRadixString(36)}';
    final folder = Directory('$dir/$day/$id')..createSync(recursive: true);
    for (final (i, p) in photos.indexed) {
      final ext = p.mediaType == 'image/png' ? 'png' : 'jpg';
      await File('${folder.path}/${i + 1}.$ext').writeAsBytes(stripMetadata(p.bytes, p.mediaType));
    }
    await File(
      '${folder.path}/meta.json',
    ).writeAsString(const JsonEncoder.withIndent(' ').convert({'id': id, 'at': now.toUtc().toIso8601String(), 'photos': photos.length, ...meta}));
    return id;
  }

  static final _part = RegExp(r'^[a-z0-9-]{1,40}$');
  static final _file = RegExp(r'^[1-6]\.(jpg|png)$');

  /// آخر المساهمات للوحة الأدمن، الأحدث أولًا، مع مسار كل صورة (يوم/رقم/ملف).
  List<Map<String, dynamic>> latest({int limit = 60, String status = ''}) {
    final out = <Map<String, dynamic>>[];
    final days = Directory(dir).listSync().whereType<Directory>().map((d) => d.uri.pathSegments.reversed.elementAt(1)).toList()..sort();
    for (final day in days.reversed) {
      final ids = Directory('$dir/$day').listSync().whereType<Directory>().map((d) => d.uri.pathSegments.reversed.elementAt(1)).toList()..sort();
      for (final id in ids.reversed) {
        final meta = File('$dir/$day/$id/meta.json');
        if (!meta.existsSync()) continue;
        final m = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
        if (status.isNotEmpty && (m['review'] ?? 'new') != status) continue;
        final files = Directory('$dir/$day/$id').listSync().map((f) => f.uri.pathSegments.last).where(_file.hasMatch).toList()..sort();
        out.add({...m, 'day': day, 'files': files});
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

  /// ملف صورة لمساهمة، بعد التأكد إن المسار ما يطلع برا المجلد.
  File? file(String day, String id, String name) {
    if (!_part.hasMatch(day) || !_part.hasMatch(id) || !_file.hasMatch(name)) return null;
    final f = File('$dir/$day/$id/$name');
    return f.existsSync() ? f : null;
  }

  Map<String, List<Map<String, dynamic>>>? _ours;
  DateTime _oursAt = DateTime(2000);

  /// صورنا المقبولة لكل نوع (رقم الموسوعة 4 أرقام ← صور)، الأحدث أولًا. كل صورة {day, id, file, part}.
  /// تنحسب كل دقيقة على الأكثر لأن التطبيق يطلبها مع كل بطاقة.
  Map<String, List<Map<String, dynamic>>> ours({DateTime? now}) {
    final t = now ?? DateTime.now();
    if (_ours != null && t.difference(_oursAt).inSeconds < 60) return _ours!;
    final out = <String, List<Map<String, dynamic>>>{};
    final root = Directory(dir);
    if (root.existsSync()) {
      final days = root.listSync().whereType<Directory>().map((d) => d.uri.pathSegments.reversed.elementAt(1)).where(_part.hasMatch).toList()..sort();
      for (final day in days.reversed) {
        final ids = Directory('$dir/$day').listSync().whereType<Directory>().map((d) => d.uri.pathSegments.reversed.elementAt(1)).toList()..sort();
        for (final id in ids.reversed) {
          final meta = File('$dir/$day/$id/meta.json');
          if (!meta.existsSync()) continue;
          final Map<String, dynamic> m;
          try {
            m = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final sp = '${m['species'] ?? ''}';
          if (m['review'] != 'approved' || !RegExp(r'^\d{4}$').hasMatch(sp)) continue;
          final parts = (m['parts'] as List?) ?? const [];
          final files = Directory('$dir/$day/$id').listSync().map((f) => f.uri.pathSegments.last).where(_file.hasMatch).toList()..sort();
          for (final f in files) {
            final i = int.parse(f.substring(0, 1)) - 1;
            out.putIfAbsent(sp, () => []).add({'day': day, 'id': id, 'file': f, 'part': i < parts.length ? '${parts[i]}' : 'other'});
          }
        }
      }
    }
    _oursAt = t;
    return _ours = out;
  }

  /// أحسن صورة عندنا للنوع تطلع في التطبيق: السمكة كاملة من جنبها، وإلا أي صورة مقبولة.
  File? bestPhoto(String sp) {
    final list = ours()[sp];
    if (list == null || list.isEmpty) return null;
    for (final part in const ['right', 'whole', 'left', 'ice']) {
      for (final p in list) {
        if (p['part'] == part) return file(p['day'] as String, p['id'] as String, p['file'] as String);
      }
    }
    final p = list.first;
    return file(p['day'] as String, p['id'] as String, p['file'] as String);
  }

  /// مراجعة الأدمن: قبول أو رفض، وتصحيح النوع إذا لزم.
  Future<Map<String, dynamic>?> review(String day, String id, {required String status, String? species}) async {
    if (!_part.hasMatch(day) || !_part.hasMatch(id) || !const {'approved', 'rejected', 'new'}.contains(status)) return null;
    final f = File('$dir/$day/$id/meta.json');
    if (!f.existsSync()) return null;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    m['review'] = status;
    if (species != null && RegExp(r'^\d{4}$').hasMatch(species)) {
      m['species'] = species;
      m['species_confirmed'] = true;
    }
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(m));
    _ours = null;
    return m;
  }
}

/// يحذف البيانات الوصفية: في JPEG أقسام APP1 إلى APP15 والتعليقات (EXIF و XMP فيها الموقع والجهاز)،
/// وفي PNG أجزاء eXIf والنصوص. الصورة نفسها ما تتغير.
Uint8List stripMetadata(Uint8List b, String mediaType) {
  if (mediaType == 'image/png') return _stripPng(b);
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return b;
  final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return b; // ملف غير متوقع، نرجعه كما هو بدل ما نخربه.
    final marker = b[i + 1];
    if (marker == 0xDA) break; // بداية بيانات الصورة: الباقي ينسخ كما هو.
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return b;
    final drop = (marker >= 0xE1 && marker <= 0xEF) || marker == 0xFE;
    if (!drop) out.add(Uint8List.sublistView(b, i, i + 2 + len));
    i += 2 + len;
  }
  out.add(Uint8List.sublistView(b, i));
  return out.takeBytes();
}

Uint8List _stripPng(Uint8List b) {
  if (b.length < 8) return b;
  const drop = {'eXIf', 'tEXt', 'iTXt', 'zTXt'};
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var i = 8;
  while (i + 12 <= b.length) {
    final len = ByteData.sublistView(b, i, i + 4).getUint32(0);
    final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
    final end = i + 12 + len;
    if (end > b.length) return b;
    if (!drop.contains(type)) out.add(Uint8List.sublistView(b, i, end));
    i = end;
  }
  return out.takeBytes();
}
