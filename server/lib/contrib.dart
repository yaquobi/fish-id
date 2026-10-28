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
