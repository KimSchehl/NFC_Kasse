import 'dart:io';

import 'package:yaml/yaml.dart';

/// The handful of layout keys bon.yaml actually has (see bon_template.yaml's
/// reference in the backend repo) — everything else about the receipt is a
/// BON_*/PRINTER_* setting in config.env, not here.
class BonLayout {
  final bool separatorBefore;
  final bool separatorAfter;
  final String separatorChar;
  final bool bold;
  final bool uppercase;
  final bool priceSameLine;
  final int blankLines;

  const BonLayout({
    this.separatorBefore = false,
    this.separatorAfter = true,
    this.separatorChar = '-',
    this.bold = true,
    this.uppercase = false,
    this.priceSameLine = true,
    this.blankLines = 0,
  });

  BonLayout copyWith({
    bool? separatorBefore,
    bool? separatorAfter,
    String? separatorChar,
    bool? bold,
    bool? uppercase,
    bool? priceSameLine,
    int? blankLines,
  }) =>
      BonLayout(
        separatorBefore: separatorBefore ?? this.separatorBefore,
        separatorAfter: separatorAfter ?? this.separatorAfter,
        separatorChar: separatorChar ?? this.separatorChar,
        bold: bold ?? this.bold,
        uppercase: uppercase ?? this.uppercase,
        priceSameLine: priceSameLine ?? this.priceSameLine,
        blankLines: blankLines ?? this.blankLines,
      );
}

class BonYamlFile {
  BonYamlFile._();

  static Future<BonLayout> load(String path) async {
    final file = File(path);
    if (!await file.exists()) return const BonLayout();
    try {
      final doc = loadYaml(await file.readAsString());
      final header = doc['header'] as YamlMap? ?? YamlMap();
      final article = doc['article'] as YamlMap? ?? YamlMap();
      final footer = doc['footer'] as YamlMap? ?? YamlMap();
      const fallback = BonLayout();
      return BonLayout(
        separatorBefore: header['separator_before'] as bool? ?? fallback.separatorBefore,
        separatorAfter: header['separator_after'] as bool? ?? fallback.separatorAfter,
        separatorChar: (header['separator_char'] as String?) ?? fallback.separatorChar,
        bold: article['bold'] as bool? ?? fallback.bold,
        uppercase: article['uppercase'] as bool? ?? fallback.uppercase,
        priceSameLine: article['price_same_line'] as bool? ?? fallback.priceSameLine,
        blankLines: footer['blank_lines'] as int? ?? fallback.blankLines,
      );
    } catch (_) {
      return const BonLayout();
    }
  }

  /// Regenerates the whole file in the same fixed format/comments as
  /// backend/bon.yaml.default every time — a hand-added comment or unusual
  /// formatting wouldn't survive a save via this tool, which is an
  /// acceptable trade-off for a structured-form editor (matches how the
  /// config.env editor only touches known key lines, but this file's nested
  /// YAML shape doesn't lend itself to the same line-preserving approach).
  static Future<void> save(String path, BonLayout layout) async {
    final content = '''
# bon.yaml — aktives Bon-Layout (ESC/POS)
# ==========================================================
# Das ist die Datei, aus der tatsächlich gedruckt wird. Änderungen werden
# erst nach einem Neustart des Backends/Dienstes übernommen — genau wie bei
# config.env.
#
# Volle Befehlsreferenz + Beispiel-Layouts: siehe bon_template.yaml daneben.
# Inhalts-Schalter (Eventname/Datum/Preis/Fußzeile/Kassierer anzeigen) stehen
# nicht hier, sondern in config.env (BON_*-Variablen).
# Maximale Zeilenbreite: PRINTER_LINE_WIDTH in config.env (Standard: 42 Zeichen)

header:
  separator_before: ${layout.separatorBefore}     # Trennlinie VOR dem Kopfbereich drucken
  separator_after: ${layout.separatorAfter}       # Trennlinie NACH dem Datum/Uhrzeit drucken
  separator_char: "${layout.separatorChar}"         # Zeichen für Trennlinie: - = * ─

article:
  bold: ${layout.bold}                  # Artikelname fett drucken
  uppercase: ${layout.uppercase}            # Artikelname in GROSSBUCHSTABEN (true/false)
  price_same_line: ${layout.priceSameLine}       # Preis rechts in gleicher Zeile (false = neue Zeile)

footer:
  blank_lines: ${layout.blankLines}              # Leerzeilen vor dem Schnitt (Papiervorschub)
''';
    await File(path).writeAsString(content);
  }
}
