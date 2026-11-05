import 'dart:io';
import 'dart:typed_data';

import 'package:fish_id/data/fish_id_api.dart';
import 'package:fish_id/data/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('queue');
    UploadQueue.debugDir = dir;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps photos while offline and sends them once the internet is back', () async {
    var online = false;
    final sent = <(int, Map<String, dynamic>)>[];
    UploadQueue.send = (images, meta) async {
      if (!online) throw const FishIdOfflineException('offline');
      sent.add((images.length, meta));
    };

    await UploadQueue.add([jpeg, jpeg, jpeg], {'species': '0220', 'days': 0, 'storage': 'ice'});
    await UploadQueue.add([jpeg], {'species': '', 'days': -1, 'storage': 'unknown'});
    expect(UploadQueue.pending.value, 2);

    expect(await UploadQueue.flush(), 0);
    expect(UploadQueue.pending.value, 2);

    online = true;
    expect(await UploadQueue.flush(), 2);
    expect(UploadQueue.pending.value, 0);
    expect(sent.map((s) => s.$1), [3, 1]);
    expect(sent.first.$2['species'], '0220');
    expect(sent.first.$2['takenAt'], isA<String>());
  });

  test('drops a contribution the server refuses, so it does not block the rest', () async {
    UploadQueue.send = (images, meta) async {
      if (meta['species'] == 'bad') throw const FishIdException('refused');
    };
    await UploadQueue.add([jpeg], {'species': 'bad'});
    await UploadQueue.add([jpeg], {'species': '0408'});
    expect(await UploadQueue.flush(), 2);
    expect(UploadQueue.pending.value, 0);
  });
}
