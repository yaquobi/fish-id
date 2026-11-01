import 'dart:convert';
import 'dart:io';

import 'package:fish_id_server/book.dart';
import 'package:test/test.dart';

void main() {
  test('links book species to KSAFish ids, forgiving small typos', () {
    final dir = Directory.systemTemp.createTempSync('book');
    File('${dir.path}/index.json').writeAsStringSync(jsonEncode({
      'species': [
        {'n': 1, 'folder': '001_Epinphelus_bleekeri', 'sci': 'Epinphelus bleekeri', 'local': ['هامور'], 'files': ['1.jpg']},
        {'n': 2, 'folder': '002_Siganus_argenteus', 'sci': 'Siganus argenteus', 'local': ['صافي'], 'files': ['1.jpg']},
        {'n': 3, 'folder': '003_Unknown_fish', 'sci': 'Unknownus fishus', 'files': []},
      ],
    }));
    Directory('${dir.path}/001_Epinphelus_bleekeri').createSync();
    File('${dir.path}/001_Epinphelus_bleekeri/1.jpg').writeAsBytesSync([1, 2, 3]);
    final book = BookArchive.open(dir.path, {'epinephelus bleekeri': 'HWT-FISH-0101', 'siganus argenteus': 'HWT-FISH-0300', 'penaeus semisulcatus': 'HWT-SHRIMP-0101'})!;
    expect([for (final s in book.species) s['ksafish']], ['HWT-FISH-0101', 'HWT-FISH-0300'], reason: 'fish without a local name are left out');
    expect(book.file('001_Epinphelus_bleekeri', '1.jpg'), isNotNull);
    expect(book.file('../accounts', '1.jpg'), isNull);
    expect(book.file('001_Epinphelus_bleekeri', 'meta.json'), isNull);
    expect(book.photo('HWT-FISH-0101')?.path, endsWith('001_Epinphelus_bleekeri/1.jpg'));
    expect(book.photo('HWT-FISH-0300'), isNull, reason: 'no photo file on disk');
    expect(book.photo('../0101'), isNull);
    expect(book.photo('HWT-SHRIMP-0101'), isNull, reason: 'a shrimp with the same four digits is a different species');
    File('${dir.path}/001_Epinphelus_bleekeri/app.jpg').writeAsBytesSync([4]);
    expect(book.photo('HWT-FISH-0101')?.path, endsWith('app.jpg'));
    dir.deleteSync(recursive: true);
  });
}
