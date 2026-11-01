import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/fish_id_api.dart';
import '../data/ksafish.dart';
import '../l10n.dart';
import '../theme.dart';

/// صورة النوع في البطاقة من سيرفرنا: صورنا من المصوّرين، وإلا صورة كتاب «أسماك البحر الأحمر».
/// تنحفظ في الجوال وتطلع على طول حتى بدون إنترنت، وتتجدد كل أسبوع عشان توصل الصور الجديدة.
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
  static final _memory = <String, (Uint8List, bool)>{};

  /// بعد كم نسأل السيرفر مرة ثانية عن صورة محفوظة (يمكن صارت لها صورة من عندنا).
  static const _refresh = Duration(days: 7);

  Uint8List? _bytes;
  bool _ours = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.species.id;
    var cached = _memory[id];
    if (cached == null && !_missing.contains(id)) {
      final file = File('${Directory.systemTemp.path}/book/$id.jpg');
      final mark = File('${Directory.systemTemp.path}/book/$id.ours');
      try {
        if (file.existsSync()) cached = (await file.readAsBytes(), mark.existsSync());
        final fresh = cached != null && DateTime.now().difference(file.lastModifiedSync()) < _refresh;
        if (!fresh) {
          final res = await http.get(Uri.parse('${apiUrl}book/$id.jpg')).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            final ours = res.headers['x-photo-source'] == 'fishid';
            cached = (res.bodyBytes, ours);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(res.bodyBytes, flush: true);
            if (ours) {
              await mark.writeAsString('1');
            } else if (mark.existsSync()) {
              await mark.delete();
            }
          } else if (res.statusCode == 404 && cached == null) {
            _missing.add(id);
          }
        }
      } catch (_) {
        // بدون إنترنت أو الكاش ما ينكتب: نعرض المحفوظ، وإلا لوحة الموسوعة.
      }
      if (cached != null) _memory[id] = cached;
    }
    if (!mounted) return;
    setState(() {
      _bytes = cached?.$1;
      _ours = cached?.$2 ?? false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return _Framed(
        image: Image.memory(_bytes!, fit: BoxFit.contain, gaplessPlayback: true),
        source: _ours
            ? tr('تصوير فريق FISH ID', 'Photo by the FISH ID team')
            : tr('المصدر: كتاب أسماك البحر الأحمر، مركز أبحاث الثروة السمكية بجدة',
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
