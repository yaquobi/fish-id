import 'dart:convert';

import 'package:flutter/services.dart';

/// نوع من موسوعة KSAFish، محمّل من assets/data/ksafish.json (تصدير الموسوعة).
class Species {
  const Species({
    required this.id,
    required this.sci,
    required this.family,
    required this.familyAr,
    required this.redSea,
    required this.gulf,
    required this.english,
    required this.code,
    required this.url,
  });

  /// معرّف حوات الكامل، مثل HWT-FISH-0408.
  final String id;
  final String sci;
  final String family;
  final String familyAr;
  final List<String> redSea;
  final List<String> gulf;
  final String english;
  final String code;
  final String url;

  /// الاسم المعروض: أول اسم محلي، وإلا الإنجليزي، وإلا العلمي.
  String get name => redSea.firstOrNull ?? gulf.firstOrNull ?? (english.isNotEmpty ? english : sci);

  factory Species.fromJson(Map<String, dynamic> j) => Species(
    id: j['id'] as String,
    sci: j['sci'] as String? ?? '',
    family: j['fam'] as String? ?? '',
    familyAr: j['famAr'] as String? ?? '',
    redSea: _names(j['red']),
    gulf: _names(j['gulf']),
    english: j['en'] as String? ?? '',
    code: j['code'] as String? ?? '',
    url: j['url'] as String? ?? '',
  );

  static List<String> _names(Object? v) =>
      (v as String? ?? '').split(RegExp(r'[|،,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// معلومة منشورة عن النوع: القياس أو الموسم أو الموئل وغيرها.
class Fact {
  const Fact(this.label, this.value, this.unit, this.scope);
  final String label;
  final String value;
  final String unit;
  final String scope;
}

class Ksafish {
  Ksafish._(this.species, this._facts) : _byId = {for (final s in species) s.id: s};

  final List<Species> species;
  final Map<String, Species> _byId;
  final Map<String, List<Fact>> _facts;

  static Future<Ksafish>? _loading;

  static Future<Ksafish> load() => _loading ??= () async {
    final j = jsonDecode(await rootBundle.loadString('assets/data/ksafish.json')) as Map<String, dynamic>;
    final species = [for (final s in j['species'] as List) Species.fromJson(s as Map<String, dynamic>)];
    final facts = <String, List<Fact>>{
      for (final e in (j['facts'] as Map<String, dynamic>).entries)
        e.key: [
          for (final f in e.value as List)
            if ((f as List)[1].toString().isNotEmpty) Fact('${f[0]}', '${f[1]}', '${f[2]}', '${f[3]}'),
        ],
    };
    return Ksafish._(species, facts);
  }();

  /// يقبل رقم حوات القصير (408 أو "0408") أو الكامل.
  Species? byId(String id) => _byId[id.startsWith('HWT-') ? id : 'HWT-FISH-${id.padLeft(4, '0')}'];

  List<Fact> factsFor(Species s) => _facts[s.id] ?? const [];

  /// بحث بالاسم المحلي أو العلمي أو الإنجليزي أو العائلة.
  List<Species> search(String q) {
    final t = _norm(q);
    if (t.isEmpty) return species;
    return species.where((s) => [s.sci, s.english, s.familyAr, s.family, ...s.redSea, ...s.gulf].any((n) => _norm(n).contains(t))).toList();
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي').replaceAll(RegExp('[ً-ْـ]'), '').trim();
}
