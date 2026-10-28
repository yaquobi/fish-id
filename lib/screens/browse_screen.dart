import 'package:flutter/material.dart';

import '../data/ksafish.dart';
import '../theme.dart';
import '../widgets/species_card.dart';

/// تصفّح أنواع KSAFish والبحث بالاسم المحلي أو العلمي، بدون إنترنت.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _db = Ksafish.load();
  String _q = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('أنواع الموسوعة')),
    body: FutureBuilder(
      future: _db,
      builder: (context, snap) {
        final db = snap.data;
        if (db == null) return const Center(child: CircularProgressIndicator(color: AppColors.navy));
        final list = db.search(_q);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ابحث: هامور، Epinephelus، شعري…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('${list.length} نوعًا', style: const TextStyle(color: AppColors.muted)),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = list[i];
                  return Card(
                    child: ListTile(
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        s.sci,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(s.name)),
                            body: ListView(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
                              children: [SpeciesCard(species: s, facts: db.factsFor(s))],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
