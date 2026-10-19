import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/backend_cli.dart';
import '../services/events_service.dart';
import '../services/service_control.dart';

const _jsonType = XTypeGroup(label: 'Festvorlage', extensions: ['json']);
const _csvType = XTypeGroup(label: 'CSV-Datei', extensions: ['csv']);

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

String _formatDateTime(DateTime d) => '${_formatDate(d)}  ${_two(d.hour)}:${_two(d.minute)}';

String _formatEuro(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

/// event.date ist `JJJJ-MM-TT` (ohne Uhrzeit, keine Zeitzone).
String? _formatEventDate(String? date) {
  final d = date == null ? null : DateTime.tryParse(date);
  return d == null ? null : _formatDate(d);
}

/// „Sommerfest 2026“ -> „Sommerfest-2026“, für vorgeschlagene Dateinamen.
String _fileStem(String name) {
  final stem = name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9ÄÖÜäöüß_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return stem.isEmpty ? 'Fest' : stem;
}

String _withExtension(String path, String ext) =>
    path.toLowerCase().endsWith(ext) ? path : '$path$ext';

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Bis zu dieser Zeitspanne seit der letzten Buchung gilt: „es wird gerade
/// noch kassiert“ — dann warnt der Start-/Beenden-Dialog deutlich.
const _recentActivitySeconds = 5 * 60;

/// „Letzte Buchung vor 12 Sekunden“ für den Start-/Beenden-Dialog, oder
/// null, wenn im aktiven Event noch nie gebucht wurde.
Widget? _lastActivityNotice(BuildContext context, EventsOverview o) {
  final secs = o.secondsSinceLastActivity;
  if (secs == null) return null;
  final theme = Theme.of(context);
  final String ago;
  if (secs < 60) {
    ago = 'vor ${_plural(secs < 0 ? 0 : secs, 'Sekunde', 'Sekunden')}';
  } else if (secs < 3600) {
    ago = 'vor ${_plural(secs ~/ 60, 'Minute', 'Minuten')}';
  } else if (secs < 86400) {
    ago = 'vor ${_plural(secs ~/ 3600, 'Stunde', 'Stunden')}';
  } else {
    ago = o.lastActivityAt == null ? 'vor über einem Tag' : 'am ${_formatDateTime(o.lastActivityAt!)}';
  }
  if (secs < _recentActivitySeconds) {
    return _Notice(
      icon: Icons.point_of_sale,
      color: theme.colorScheme.error,
      text: 'Letzte Buchung $ago — an den Kassen wird offenbar noch gebucht. Eine Buchung, '
          'die genau beim Wechsel ankommt, wird abgelehnt und muss am Tablet wiederholt werden.',
    );
  }
  return _Notice(
    icon: Icons.schedule,
    color: theme.colorScheme.outline,
    text: 'Letzte Buchung $ago.',
  );
}

/// Wechsel zwischen internem Betrieb und einem Fest, Festvorlagen und der
/// CSV-Export für die Buchhaltung. Alles läuft über EventsService
/// (NfcKasseBackend.exe), auch bei laufendem Dienst — die Tablets merken den
/// Wechsel über ihre regelmäßige /health-Abfrage von selbst.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  String? _busyText;

  bool get _busy => _busyText != null;

  void _refresh() {
    ref.read(eventsRefreshProvider.notifier).state++;
    // Vor jedem Festwechsel entsteht eine Sicherung — die soll im
    // Daten-Bereich auch gleich auftauchen.
    ref.read(backupRefreshProvider.notifier).state++;
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Führt [task] mit Fortschrittsanzeige aus. Fehler werden angezeigt,
  /// der Rückgabewert sagt, ob alles geklappt hat.
  Future<bool> _guard(String busyText, Future<void> Function() task) async {
    setState(() => _busyText = busyText);
    try {
      await task();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  /// Frisch geladener Stand für die Start-/Beenden-Dialoge: letzte Buchung,
  /// offene Bons und Chip-Guthaben ändern sich laufend.
  Future<EventsOverview?> _freshOverview() async {
    EventsOverview? fresh;
    final ok = await _guard('Stand wird geprüft …', () async {
      fresh = await EventsService.overview();
    });
    return ok ? fresh : null;
  }

  Future<void> _startFest() async {
    final overview = await _freshOverview();
    if (overview == null || !mounted) return;
    if (!overview.active.isIntern) {
      _refresh();
      return;
    }
    final options = await showDialog<EventStartOptions>(
      context: context,
      builder: (_) => _StartFestDialog(overview: overview),
    );
    if (options == null) return;

    var needsRestart = false;
    final ok = await _guard('Fest wird gestartet, vorher wird gesichert …', () async {
      needsRestart = await EventsService.start(options);
    });
    if (!mounted) return;
    _refresh();
    if (!ok) return;
    if (needsRestart) {
      // Konfiguration/Bon-Layout zeigen sonst noch den alten Stand der Dateien.
      ref.read(configRefreshProvider.notifier).state++;
      await _offerRestart();
    } else {
      _snack('Fest „${options.name}“ gestartet. Die Tablets wechseln in wenigen Sekunden.');
    }
  }

  Future<void> _offerRestart() async {
    final restart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fest gestartet'),
        content: const Text(
          'Die Einstellungen aus der Vorlage (Bon-Layout, Drucker, Texte) wurden übernommen. '
          'Sie gelten erst nach einem Neustart des Dienstes.\n\n'
          'Jetzt neu starten? Die Tablets sind dabei einige Sekunden nicht verbunden.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Jetzt neu starten')),
        ],
      ),
    );
    if (!mounted) return;
    if (restart != true) {
      _snack('Fest gestartet. Bitte den Dienst später neu starten, damit die Einstellungen gelten.');
      return;
    }
    final ok = await _guard('Dienst wird neu gestartet …', () async {
      if (!await ServiceControl.restart()) {
        throw const BackendCliException('Der Dienst konnte nicht neu gestartet werden.');
      }
    });
    if (ok && mounted) _snack('Dienst neu gestartet, die Einstellungen gelten jetzt.');
  }

  Future<void> _endFest() async {
    final o = await _freshOverview();
    if (o == null || !mounted) return;
    if (o.active.isIntern) {
      _refresh();
      return;
    }

    final theme = Theme.of(context);
    final activityNotice = _lastActivityNotice(context, o);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Fest „${o.active.name}“ beenden?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Das Fest wird archiviert, und die Kasse wechselt in den internen Betrieb. '
                'Guthaben und Chips bleiben vollständig erhalten. Vorher wird automatisch '
                'eine Sicherung angelegt.',
              ),
              ?activityNotice,
              if (o.openPrintJobs > 0)
                _Notice(
                  icon: Icons.print_outlined,
                  color: theme.colorScheme.error,
                  text: '${o.openPrintJobs} Bon(s) sind noch nicht gedruckt.',
                ),
              if (o.openPagerOrders > 0)
                _Notice(
                  icon: Icons.vibration,
                  color: theme.colorScheme.error,
                  text: '${o.openPagerOrders} offene Pager-Bestellung(en) werden als erledigt markiert.',
                ),
              if (o.chipsWithBalance > 0)
                _Notice(
                  icon: Icons.contactless_outlined,
                  color: theme.colorScheme.primary,
                  text: '${o.chipsWithBalance} Chip(s) mit zusammen ${_formatEuro(o.chipsBalanceTotal)} '
                      'Restguthaben — das Guthaben bleibt für das nächste Fest erhalten.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Fest beenden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _guard('Fest wird beendet, vorher wird gesichert …', EventsService.end);
    if (!mounted) return;
    _refresh();
    if (ok) _snack('Fest beendet — die Kasse läuft jetzt intern.');
  }

  Future<void> _exportPreset(KasseEvent event) async {
    final location = await getSaveLocation(
      suggestedName: 'Festvorlage_${_fileStem(event.displayName)}.json',
      acceptedTypeGroups: const [_jsonType],
    );
    if (location == null) return;
    final path = _withExtension(location.path, '.json');
    final ok = await _guard('Vorlage wird gespeichert …', () => EventsService.exportPreset(event.id, path));
    if (ok && mounted) _snack('Festvorlage gespeichert: $path');
  }

  Future<void> _exportCsv(KasseEvent event) async {
    int? periodId;
    if (event.periods.length > 1) {
      final choice = await showDialog<({int? periodId})>(
        context: context,
        builder: (_) => _CsvPeriodDialog(event: event),
      );
      if (choice == null) return;
      periodId = choice.periodId;
    }
    final location = await getSaveLocation(
      suggestedName: 'Abrechnung_${_fileStem(event.displayName)}.csv',
      acceptedTypeGroups: const [_csvType],
    );
    if (location == null) return;
    final path = _withExtension(location.path, '.csv');
    var rows = 0;
    final ok = await _guard('CSV wird erstellt …', () async {
      rows = await EventsService.exportCsv(event.id, path, periodId: periodId);
    });
    if (ok && mounted) _snack('Abrechnung gespeichert ($rows Buchung(en)): $path');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overviewAsync = ref.watch(eventsOverviewProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Feste', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Die Kasse läuft entweder intern oder in einem Fest. Guthaben und Chips bleiben '
            'beim Wechsel immer erhalten, vorher wird automatisch eine Sicherung angelegt. '
            'Die Tablets übernehmen den Wechsel nach wenigen Sekunden von selbst.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          overviewAsync.when(
            loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
            error: (e, _) => Text(
              'Feste konnten nicht geladen werden: $e',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            data: (o) => _CurrentCard(
              overview: o,
              enabled: !_busy,
              onStart: _startFest,
              onEnd: _endFest,
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_busyText!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Alle Feste', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Aktualisieren',
                icon: const Icon(Icons.refresh),
                onPressed: _busy ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: overviewAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const SizedBox.shrink(),
              data: (o) => ListView.separated(
                itemCount: o.events.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _EventTile(
                  event: o.events[i],
                  enabled: !_busy,
                  onExportPreset: () => _exportPreset(o.events[i]),
                  onExportCsv: () => _exportCsv(o.events[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CurrentCard extends StatelessWidget {
  final EventsOverview overview;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _CurrentCard({
    required this.overview,
    required this.enabled,
    required this.onStart,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = overview.active;
    final details = active.isIntern
        ? 'Kein Fest aktiv. Buchungen laufen auf „Intern“ mit eigener Statistik.'
        : [
            if (active.startedAt != null) 'Seit ${_formatDateTime(active.startedAt!)}',
            if (_formatEventDate(active.date) != null) 'Festdatum ${_formatEventDate(active.date)}',
            'Pfand ${_formatEuro(active.chipDeposit)}',
            '${active.sales} Buchung(en)',
          ].join('  ·  ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              active.isIntern ? Icons.home_work_outlined : Icons.celebration,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active.isIntern ? 'Interner Betrieb' : 'Fest läuft: ${active.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(details, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (active.isIntern)
              FilledButton.icon(
                onPressed: enabled ? onStart : null,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Fest starten …'),
              )
            else
              FilledButton.icon(
                onPressed: enabled ? onEnd : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Fest beenden …'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final KasseEvent event;
  final bool enabled;
  final VoidCallback onExportPreset;
  final VoidCallback onExportCsv;

  const _EventTile({
    required this.event,
    required this.enabled,
    required this.onExportPreset,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final date = _formatEventDate(event.date);
    final details = [
      if (event.isIntern) 'Dauerhaft',
      if (date != null) 'Festdatum $date',
      if (!event.isIntern && event.startedAt != null) 'Beginn ${_formatDateTime(event.startedAt!)}',
      if (event.endedAt != null) 'Ende ${_formatDateTime(event.endedAt!)}',
      '${event.sales} Buchung(en)',
    ].join('  ·  ');

    return Card(
      child: ListTile(
        leading: Icon(
          event.isIntern
              ? Icons.home_work_outlined
              : event.active
                  ? Icons.celebration
                  : Icons.inventory_2_outlined,
        ),
        title: Text(event.active ? '${event.displayName}  ·  aktiv' : event.displayName),
        subtitle: Text(details),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Als Festvorlage speichern',
              icon: const Icon(Icons.description_outlined),
              onPressed: enabled ? onExportPreset : null,
            ),
            IconButton(
              tooltip: 'Abrechnung als CSV (Buchungen, Artikel, Gesamtstatistik)',
              icon: const Icon(Icons.table_view_outlined),
              onPressed: enabled ? onExportCsv : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Zeitraum für den CSV-Export: das ganze Fest oder ein einzelner
/// Abschnitt zwischen zwei Tagesabschlüssen. Gibt `(periodId: null)` für
/// das ganze Fest zurück, `null` bei Abbruch.
class _CsvPeriodDialog extends StatefulWidget {
  final KasseEvent event;

  const _CsvPeriodDialog({required this.event});

  @override
  State<_CsvPeriodDialog> createState() => _CsvPeriodDialogState();
}

class _CsvPeriodDialogState extends State<_CsvPeriodDialog> {
  int? _periodId;

  String _label(StatsPeriodInfo p) {
    final from = p.startedAt == null ? '?' : _formatDateTime(p.startedAt!);
    final to = p.closedAt == null ? 'läuft' : _formatDateTime(p.closedAt!);
    return '${p.label}  ($from – $to)';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('CSV-Export: ${widget.event.displayName}'),
      content: SizedBox(
        width: 460,
        child: RadioGroup<int?>(
          groupValue: _periodId,
          onChanged: (v) => setState(() => _periodId = v),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RadioListTile<int?>(value: null, title: Text('Gesamter Zeitraum')),
                for (final p in widget.event.periods)
                  RadioListTile<int?>(value: p.id, title: Text(_label(p))),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (periodId: _periodId)),
          child: const Text('Weiter'),
        ),
      ],
    );
  }
}

const _sourceEmpty = 'empty';
const _sourceFile = 'file';

/// Neues Fest: Name und Pfand (Pflicht), Datum, und welche Warengruppen und
/// Artikel es zeigt — übernommen aus Intern, einem früheren Fest oder einer
/// Vorlagen-Datei. Warengruppen und Artikel gehören dem Veranstalter; ein Fest
/// schaltet sie nur ein. Gibt die gewählten [EventStartOptions] zurück,
/// gestartet wird im Screen.
class _StartFestDialog extends StatefulWidget {
  final EventsOverview overview;

  const _StartFestDialog({required this.overview});

  @override
  State<_StartFestDialog> createState() => _StartFestDialogState();
}

class _StartFestDialogState extends State<_StartFestDialog> {
  final _name = TextEditingController();
  final _deposit = TextEditingController();
  DateTime? _date;
  late String _source;
  PresetSummary? _preset;
  bool _includeArticles = true;
  bool _includeBonLayout = false;
  bool _includePrinter = false;
  bool _includeBonText = false;
  bool _resetStock = false;
  Set<int> _categoryIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    // Meist kommen die Artikel vom letzten Fest — das ist der Vorschlag.
    final lastFest = widget.overview.events.where((e) => !e.isIntern).firstOrNull;
    _setSource(lastFest == null ? _sourceEmpty : '${lastFest.id}');
  }

  /// Wählt die Quelle und schlägt deren Warengruppen vor.
  void _setSource(String source) {
    _source = source;
    final eventId = int.tryParse(source);
    _categoryIds = {
      for (final c in widget.overview.categories)
        if (eventId != null && c.eventIds.contains(eventId)) c.id,
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _deposit.dispose();
    super.dispose();
  }

  bool get _hasArticles => _source == _sourceFile ? _includeArticles : _categoryIds.isNotEmpty;

  bool get _needsRestart =>
      _source == _sourceFile && (_includeBonLayout || _includePrinter || _includeBonText);

  String _sourceLabel(KasseEvent e) {
    if (e.isIntern) return 'Artikel aus „Intern“';
    final date = _formatEventDate(e.date) ?? (e.startedAt == null ? null : _formatDate(e.startedAt!));
    return date == null ? 'Artikel aus „${e.name}“' : 'Artikel aus „${e.name}“ ($date)';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPreset() async {
    final file = await openFile(acceptedTypeGroups: const [_jsonType]);
    if (file == null) return; // Auswahl bleibt, wie sie war
    try {
      final preset = await PresetSummary.read(file.path);
      if (!mounted) return;
      setState(() {
        _source = _sourceFile;
        _preset = preset;
        _includeArticles = preset.categories > 0 || preset.products > 0;
        _includeBonLayout = preset.hasBonLayout;
        _includePrinter = preset.hasPrinter;
        _includeBonText = preset.hasBonText;
        _error = null;
        // Vorschläge aus der Vorlage, beide frei änderbar.
        if (_name.text.trim().isEmpty && (preset.sourceEventName ?? '').isNotEmpty) {
          _name.text = preset.sourceEventName!;
        }
        if (preset.chipDeposit != null) {
          _deposit.text = preset.chipDeposit!.toStringAsFixed(2).replaceAll('.', ',');
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bitte einen Festnamen eingeben.');
      return;
    }
    if (_deposit.text.trim().isEmpty) {
      setState(() => _error = 'Bitte den Pfand pro Chip eingeben (0 für kein Pfand).');
      return;
    }
    final deposit = double.tryParse(_deposit.text.trim().replaceAll(',', '.'));
    if (deposit == null || deposit < 0) {
      setState(() => _error = 'Ungültiger Pfand-Betrag (Beispiel: 3,00).');
      return;
    }
    final fromFile = _source == _sourceFile;
    Navigator.pop(
      context,
      EventStartOptions(
        name: name,
        date: _date == null ? null : '${_date!.year}-${_two(_date!.month)}-${_two(_date!.day)}',
        chipDeposit: deposit,
        resetStock: _hasArticles && _resetStock,
        categoryIds: fromFile ? null : _categoryIds.toList(),
        sourceEventId: fromFile || _source == _sourceEmpty ? null : int.parse(_source),
        presetPath: fromFile ? _preset!.path : null,
        includeArticles: _includeArticles,
        includeBonLayout: fromFile && _includeBonLayout,
        includePrinter: fromFile && _includePrinter,
        includeBonText: fromFile && _includeBonText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _preset;

    return AlertDialog(
      title: const Text('Fest starten'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_lastActivityNotice(context, widget.overview) case final notice?) ...[
                notice,
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Festname *',
                  helperText: 'Steht auf jedem Bon. Später änderbar unter Konfiguration.',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deposit,
                      decoration: const InputDecoration(
                        labelText: 'Pfand pro Chip (€) *',
                        hintText: 'z. B. 3,00 — 0 für kein Pfand',
                        helperText: 'Gilt für neu ausgegebene Chips',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(_date == null ? 'Datum (optional)' : _formatDate(_date!)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Artikel & Warengruppen'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _source,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: _sourceEmpty, child: Text('Ohne Vorlage — Warengruppen unten wählen')),
                      for (final e in widget.overview.events)
                        DropdownMenuItem(value: '${e.id}', child: Text(_sourceLabel(e))),
                      DropdownMenuItem(
                        value: _sourceFile,
                        child: Text(preset == null
                            ? 'Aus Vorlagen-Datei …'
                            : 'Aus Vorlage: ${preset.path.split(r'\').last}'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == _sourceFile) {
                        _pickPreset();
                      } else {
                        setState(() {
                          _setSource(v);
                          _error = null;
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_source == _sourceFile && preset != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('Was soll aus der Vorlage übernommen werden?',
                          style: theme.textTheme.labelLarge),
                    ),
                    TextButton(onPressed: _pickPreset, child: const Text('Andere Datei …')),
                  ],
                ),
                CheckboxListTile(
                  value: _includeArticles,
                  onChanged: (v) => setState(() => _includeArticles = v ?? false),
                  title: Text('Artikel & Warengruppen '
                      '(${preset.categories} Warengruppen, ${preset.products} Artikel)'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (preset.hasBonLayout)
                  CheckboxListTile(
                    value: _includeBonLayout,
                    onChanged: (v) => setState(() => _includeBonLayout = v ?? false),
                    title: const Text('Bon-Layout'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                if (preset.hasPrinter)
                  CheckboxListTile(
                    value: _includePrinter,
                    onChanged: (v) => setState(() => _includePrinter = v ?? false),
                    title: const Text('Drucker-Einstellungen'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                if (preset.hasBonText)
                  CheckboxListTile(
                    value: _includeBonText,
                    onChanged: (v) => setState(() => _includeBonText = v ?? false),
                    title: const Text('Fußzeile & Kassierer-Text'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                if (_needsRestart)
                  Text(
                    'Bon-Layout, Drucker und Texte gelten erst nach einem Neustart des Dienstes — '
                    'das Admin-Tool bietet ihn direkt nach dem Start an.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
              if (_source != _sourceFile) ...[
                const SizedBox(height: 12),
                Text('Warengruppen in diesem Fest', style: theme.textTheme.labelLarge),
                Text(
                  'Warengruppen und Artikel gehören dem Veranstalter, das Fest schaltet sie nur ein. '
                  'Neu gewählte Warengruppen kommen mit allen Artikeln. Einzelne Artikel schaltest du '
                  'in der Kasse unter Artikelverwaltung ein und aus.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                if (widget.overview.categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Noch keine Warengruppen — sie werden in der Kasse angelegt.'),
                  ),
                for (final c in widget.overview.categories)
                  CheckboxListTile(
                    value: _categoryIds.contains(c.id),
                    onChanged: (v) => setState(() {
                      v == true ? _categoryIds.add(c.id) : _categoryIds.remove(c.id);
                    }),
                    title: Text(c.name),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
              SwitchListTile(
                value: _hasArticles && _resetStock,
                onChanged: _hasArticles ? (v) => setState(() => _resetStock = v) : null,
                title: const Text('Bestände zurücksetzen'),
                subtitle: const Text('Alle Artikel dieses Fests starten ohne Bestandszählung (unbegrenzt). '
                    'Sonst zählt der Bestand weiter, er gehört dem Artikel.'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _source == _sourceFile && preset == null ? null : _submit,
          child: const Text('Fest starten'),
        ),
      ],
    );
  }
}
