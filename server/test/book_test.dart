import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/book.dart';
import 'package:test/test.dart';

void main() {
  test('links book species to KSAFish ids, forgiving small typos', () {
    final dir = Directory.systemTemp.createTempSync('book');
    File('${dir.path}/index.json').writeAsStringSync(jsonEncode({
      'species': [
        {'n': 1, 'folder': '001_Epinphelus_bleekeri', 'sci': 'Epinphelus bleekeri', 'files': ['1.jpg']},
        {'n': 2, 'folder': '002_Siganus_argenteus', 'sci': 'Siganus argenteus', 'files': ['1.jpg']},
        {'n': 3, 'folder': '003_Unknown_fish', 'sci': 'Unknownus fishus', 'files': []},
      ],
    }));
    Directory('${dir.path}/001_Epinphelus_bleekeri').createSync();
    File('${dir.path}/001_Epinphelus_bleekeri/1.jpg').writeAsBytesSync([1, 2, 3]);
    final book = BookArchive.open(dir.path, {'epinephelus bleekeri': '0101', 'siganus argenteus': '0300'})!;
    expect([for (final s in book.species) s['ksafish']], ['0101', '0300', null]);
    expect(book.file('001_Epinphelus_bleekeri', '1.jpg'), isNotNull);
    expect(book.file('../accounts', '1.jpg'), isNull);
    expect(book.file('001_Epinphelus_bleekeri', 'meta.json'), isNull);
    dir.deleteSync(recursive: true);
  });
}
