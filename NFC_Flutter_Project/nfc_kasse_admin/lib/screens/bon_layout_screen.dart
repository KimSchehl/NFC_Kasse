import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/bon_yaml_file.dart';
import '../services/nfc_kasse_paths.dart';

/// Structured form for bon.yaml's few layout keys — everything else about
/// the receipt (content toggles) lives on the Konfiguration screen as
/// BON_*/PRINTER_* settings in config.env.
class BonLayoutScreen extends ConsumerStatefulWidget {
  const BonLayoutScreen({super.key});

  @override
  ConsumerState<BonLayoutScreen> createState() => _BonLayoutScreenState();
}

class _BonLayoutScreenState extends ConsumerState<BonLayoutScreen> {
  BonLayout _layout = const BonLayout();
  bool _populated = false;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await BonYamlFile.save(NfcKassePaths.bonYamlPath, _layout);
    if (!mounted) return;
    ref.read(configRefreshProvider.notifier).state++;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Gespeichert — Neustart nötig, damit die Änderungen wirken.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final layoutAsync = ref.watch(bonLayoutProvider);
    final theme = Theme.of(context);

    return layoutAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('bon.yaml konnte nicht gelesen werden: $e')),
      data: (loaded) {
        if (!_populated) {
          _layout = loaded;
          _populated = true;
        }
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bon-Layout', style: theme.textTheme.headlineSmall),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 16),
                      child: Text(
                        'Reines Layout — Inhalts-Schalter (Eventname, Preis, Fußzeile, '
                        'Kassierer) stehen auf der Konfiguration-Seite.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Trennlinie vor dem Kopfbereich'),
                      value: _layout.separatorBefore,
                      onChanged: (v) => setState(() => _layout = _layout.copyWith(separatorBefore: v)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Trennlinie nach Datum/Uhrzeit'),
                      value: _layout.separatorAfter,
                      onChanged: (v) => setState(() => _layout = _layout.copyWith(separatorAfter: v)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: DropdownButtonFormField<String>(
                        initialValue: _layout.separatorChar,
                        decoration: const InputDecoration(labelText: 'Trennzeichen', isDense: true),
                        items: const ['-', '=', '*', '─']
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _layout = _layout.copyWith(separatorChar: v));
                        },
                      ),
                    ),
                    const Divider(height: 32),
                    SwitchListTile(
                      title: const Text('Artikelname fett'),
                      value: _layout.bold,
                      onChanged: (v) => setState(() => _layout = _layout.copyWith(bold: v)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Artikelname in GROSSBUCHSTABEN'),
                      value: _layout.uppercase,
                      onChanged: (v) => setState(() => _layout = _layout.copyWith(uppercase: v)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Preis in derselben Zeile wie der Artikel'),
                      subtitle: const Text('Aus = Preis in eigener, rechtsbündiger Zeile'),
                      value: _layout.priceSameLine,
                      onChanged: (v) => setState(() => _layout = _layout.copyWith(priceSameLine: v)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextFormField(
                        initialValue: _layout.blankLines.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Leerzeilen vor dem Abschneiden',
                          helperText: 'Papiervorschub',
                          isDense: true,
                        ),
                        onChanged: (v) => _layout = _layout.copyWith(blankLines: int.tryParse(v) ?? _layout.blankLines),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Speichern'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
