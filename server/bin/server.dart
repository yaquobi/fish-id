import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/app.dart';
import 'package:fish_id_server/claude.dart';
import 'package:fish_id_server/refs.dart';
import 'package:shelf/shelf_io.dart' as io;

/// الإعدادات من متغيرات البيئة (ملف .env في docker compose):
/// ANTHROPIC_API_KEY إلزامي، و FISHID_MODEL و FISHID_EFFORT و FISHID_PROMPT و FISHID_PER_MINUTE و PORT اختيارية.
Future<void> main() async {
  final env = Platform.environment;
  final key = env['ANTHROPIC_API_KEY'] ?? '';
  final dataPath = env['KSAFISH_JSON'] ?? 'data/ksafish.json';
  final data = jsonDecode(await File(dataPath).readAsString()) as Map<String, dynamic>;

  final ai = key.isEmpty
      ? null
      : FishIdAi(
          key: key,
          speciesList: FishIdAi.speciesListFrom(data),
          model: env['FISHID_MODEL'] ?? 'claude-opus-5-5',
          effort: env['FISHID_EFFORT'] ?? 'low',
          prompt: env['FISHID_PROMPT'] ?? 'v1',
          // الصور المرجعية للأنواع المتشابهة، تنبنى بـ bash server/eval.sh refs. إذا المجلد فاضي تنطفي المرحلة الثانية.
          refs: RefLibrary.load(env['FISHID_REFS'] ?? 'refs', data),
          refsBelow: int.tryParse(env['FISHID_REFS_BELOW'] ?? '') ?? 80,
        );
  if (ai == null) stderr.writeln('FishId: ANTHROPIC_API_KEY غير موجود، الخدمة ترجع «غير مفعّلة».');

  final app = FishIdApp(identify: ai?.identify, perMinute: int.tryParse(env['FISHID_PER_MINUTE'] ?? '') ?? 30);
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(app.handler, InternetAddress.anyIPv4, port);
  stdout.writeln('FishId: يستمع على المنفذ ${server.port}، ${(data['species'] as List).length} نوعًا');
}
