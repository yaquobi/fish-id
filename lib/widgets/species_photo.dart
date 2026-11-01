import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/fish_id_api.dart';
import '../data/ksafish.dart';
import '../l10n.dart';
import '../theme.dart';

/// صورة النوع في البطاقة: صورة كتاب «أسماك البحر الأحمر» من سيرفرنا (مصغّرة وسريعة)،
/// تنحفظ في الجوال أول مرة وبعدها تطلع على طول حتى بدون إنترنت.
/// إذا النوع ما له صورة في الكتاب نعرض لوحته من موقع KSAFish زي قبل، وإذا ما فيه شي تختفي بهدوء.
class SpeciesPhoto extends StatefulWidget {
  const SpeciesPhoto(this.species, {super.key});
  final Species species;

  @override
  State<SpeciesPhoto> createState() => _SpeciesPhotoState();
}

class _SpeciesPhotoState extends State<SpeciesPhoto> {
  /// الأنواع اللي تأكدنا إنها ما لها صورة كتاب، عشان ما نسأل السيرفر كل مرة.
  static final _missing = <String>{};
  static final _memory = <String, Uint8List>{};

  Uint8List? _bytes;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.species.id;
    var bytes = _memory[id];
    if (bytes == null && !_missing.contains(id)) {
      try {
        final file = File('${Directory.systemTemp.path}/book/$id.jpg');
        if (file.existsSync()) {
          bytes = await file.readAsBytes();
        } else {
          final res = await http.get(Uri.parse('${apiUrl}book/$id.jpg')).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            bytes = res.bodyBytes;
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
          } else if (res.statusCode == 404) {
            _missing.add(id);
          }
        }
      } catch (_) {
        // بدون إنترنت أو الكاش ما ينكتب: نرجع للوحة الموسوعة.
      }
      if (bytes != null) _memory[id] = bytes;
    }
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return _Framed(
        image: Image.memory(_bytes!, fit: BoxFit.contain, gaplessPlayback: true),
        source: tr('المصدر: كتاب أسماك البحر الأحمر، مركز أبحاث الثروة السمكية بجدة',
            'Source: Red Sea Fishes book, Jeddah Fisheries Research Center'),
      );
    }
    final plate = widget.species.plateUrl;
    if (!_done || plate == null) return const SizedBox.shrink();
    return Image.network(
      plate,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, _) => frame == null
          ? const SizedBox.shrink()
          : _Framed(image: child, source: tr('المصدر: موسوعة KSAFish', 'Source: KSAFish encyclopedia')),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.image, required this.source});
  final Widget image;
  final String source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: image,
        ),
        const SizedBox(height: 4),
        Text(source, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    ),
  );
}
