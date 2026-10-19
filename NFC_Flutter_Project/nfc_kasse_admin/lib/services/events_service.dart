import 'dart:convert';
import 'dart:io';

import 'backend_cli.dart';

/// Zeitstempel aus der Datenbank sind UTC im SQLite-Format
/// `JJJJ-MM-TT HH:MM:SS` — für die Anzeige in Ortszeit umrechnen.
DateTime? parseDbTimestamp(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z')?.toLocal();
}

class StatsPeriodInfo {
  final int id;
  final String label;
  final DateTime? startedAt;
  final DateTime? closedAt;

  const StatsPeriodInfo({required this.id, required this.label, this.startedAt, this.closedAt});

  factory StatsPeriodInfo.fromJson(Map<String, dynamic> j) => StatsPeriodInfo(
        id: j['id'] as int,
        label: j['label'] as String,
        startedAt: parseDbTimestamp(j['started_at'] as String?),
        closedAt: parseDbTimestamp(j['closed_at'] as String?),
      );
}

/// Ein Fest oder das dauerhafte „Intern“-Event.
class KasseEvent {
  final int id;
  final String name;
  final String? date;
  final bool active;
  final bool isIntern;
  final double chipDeposit;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<StatsPeriodInfo> periods;
  final int sales;

  const KasseEvent({
    required this.id,
    required this.name,
    this.date,
    required this.active,
    required this.isIntern,
    required this.chipDeposit,
    this.startedAt,
    this.endedAt,
    this.periods = const [],
    this.sales = 0,
  });

  factory KasseEvent.fromJson(Map<String, dynamic> j) => KasseEvent(
        id: j['id'] as int,
        name: j['name'] as String,
        date: j['date'] as String?,
        active: j['active'] as bool,
        isIntern: j['is_intern'] as bool,
        chipDeposit: (j['chip_deposit'] as num).toDouble(),
        startedAt: parseDbTimestamp(j['started_at'] as String?),
        endedAt: parseDbTimestamp(j['ended_at'] as String?),
        periods: [
          for (final p in (j['periods'] as List? ?? const []))
            StatsPeriodInfo.fromJson(p as Map<String, dynamic>),
        ],
        sales: j['sales'] as int? ?? 0,
      );

  String get displayName => isIntern ? 'Intern' : name;
}

/// Eine Kategorie des Veranstalters und die Events, in denen sie
/// eingeschaltet ist (für die Auswahl im „Fest starten“-Dialog).
class CategoryInfo {
  final int id;
  final String name;
  final List<int> eventIds;

  const CategoryInfo({required this.id, required this.name, this.eventIds = const []});

  factory CategoryInfo.fromJson(Map<String, dynamic> j) => CategoryInfo(
        id: j['id'] as int,
        name: j['name'] as String,
        eventIds: [for (final e in (j['event_ids'] as List? ?? const [])) e as int],
      );
}

class EventsOverview {
  final List<KasseEvent> events;
  final List<CategoryInfo> categories;
  final int activeEventId;

  /// Letzte Buchung, Aufladung oder Auszahlung im aktiven Event — null,
  /// wenn dort noch nichts passiert ist.
  final DateTime? lastActivityAt;
  final int? secondsSinceLastActivity;
  final int openPrintJobs;
  final int openPagerOrders;
  final int chipsWithBalance;
  final double chipsBalanceTotal;

  const EventsOverview({
    required this.events,
    this.categories = const [],
    required this.activeEventId,
    this.lastActivityAt,
    this.secondsSinceLastActivity,
    required this.openPrintJobs,
    required this.openPagerOrders,
    required this.chipsWithBalance,
    required this.chipsBalanceTotal,
  });

  factory EventsOverview.fromJson(Map<String, dynamic> j) => EventsOverview(
        events: [for (final e in j['events'] as List) KasseEvent.fromJson(e as Map<String, dynamic>)],
        categories: [
          for (final c in (j['categories'] as List? ?? const []))
            CategoryInfo.fromJson(c as Map<String, dynamic>),
        ],
        activeEventId: j['active_event_id'] as int,
        lastActivityAt: parseDbTimestamp(j['last_activity_at'] as String?),
        secondsSinceLastActivity: j['seconds_since_last_activity'] as int?,
        openPrintJobs: j['open_print_jobs'] as int,
        openPagerOrders: j['open_pager_orders'] as int,
        chipsWithBalance: j['chips_with_balance'] as int,
        chipsBalanceTotal: (j['chips_balance_total'] as num).toDouble(),
      );

  KasseEvent get active => events.firstWhere((e) => e.id == activeEventId);
}

/// Was eine Festvorlagen-Datei enthält — für die Vorschau und die
/// Häkchen im „Fest starten“-Dialog. Geprüft wird die Datei erst vom
/// Backend beim Start; hier reicht es, sie lesen zu können.
class PresetSummary {
  final String path;
  final String? sourceEventName;
  final double? chipDeposit;
  final int categories;
  final int products;
  final bool hasBonLayout;
  final bool hasPrinter;
  final bool hasBonText;

  const PresetSummary({
    required this.path,
    this.sourceEventName,
    this.chipDeposit,
    required this.categories,
    required this.products,
    required this.hasBonLayout,
    required this.hasPrinter,
    required this.hasBonText,
  });

  static Future<PresetSummary> read(String path) async {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw const BackendCliException('Die Datei ist keine gültige Festvorlage.');
    }
    bool present(String key) => j[key] is Map && (j[key] as Map).isNotEmpty;
    return PresetSummary(
      path: path,
      sourceEventName: j['source_event_name'] as String?,
      chipDeposit: (j['chip_deposit'] as num?)?.toDouble(),
      categories: (j['categories'] as List? ?? const []).length,
      products: (j['products'] as List? ?? const []).length,
      hasBonLayout: present('bon_layout'),
      hasPrinter: present('printer'),
      hasBonText: present('bon_text'),
    );
  }
}

/// Woher die Artikel eines neuen Fests kommen: leer, aus einem
/// vorhandenen Event (Intern oder archiviertes Fest) oder aus einer Datei.
/// Kategorien und Artikel gehören dem Veranstalter — ein Fest schaltet sie
/// nur ein, [categoryIds] wählt die Kategorien (null = wie die Quelle).
class EventStartOptions {
  final String name;
  final String? date;
  final double chipDeposit;
  final bool resetStock;
  final List<int>? categoryIds;
  final int? sourceEventId;
  final String? presetPath;
  final bool includeArticles;
  final bool includeBonLayout;
  final bool includePrinter;
  final bool includeBonText;

  const EventStartOptions({
    required this.name,
    this.date,
    required this.chipDeposit,
    this.resetStock = false,
    this.categoryIds,
    this.sourceEventId,
    this.presetPath,
    this.includeArticles = true,
    this.includeBonLayout = false,
    this.includePrinter = false,
    this.includeBonText = false,
  });
}

/// Fest starten/beenden, Festvorlagen und CSV-Export. Die Arbeit macht
/// admin_cli.py in NfcKasseBackend.exe — dieselben Regeln wie überall,
/// inklusive automatischer Sicherung vor jedem Festwechsel.
class EventsService {
  EventsService._();

  static Future<EventsOverview> overview() async =>
      EventsOverview.fromJson(await BackendCli.run(['events']));

  /// Liefert true, wenn Drucker-/Bon-Einstellungen aus der Vorlage
  /// geschrieben wurden — die gelten erst nach einem Neustart des Dienstes.
  static Future<bool> start(EventStartOptions o) async {
    final json = await BackendCli.run([
      'event-start',
      '--name', o.name,
      if (o.date != null) ...['--date', o.date!],
      '--deposit', o.chipDeposit.toStringAsFixed(2),
      o.resetStock ? '--reset-stock' : '--keep-stock',
      if (o.categoryIds != null) ...['--categories', o.categoryIds!.join(',')],
      if (o.sourceEventId != null) ...['--source-event', '${o.sourceEventId}'],
      if (o.presetPath != null) ...[
        '--preset', o.presetPath!,
        if (!o.includeArticles) '--no-articles',
        if (o.includeBonLayout) '--bon-layout',
        if (o.includePrinter) '--printer',
        if (o.includeBonText) '--bon-text',
      ],
    ]);
    return json['needs_restart'] as bool? ?? false;
  }

  /// Ändert Name und/oder Pfand des laufenden Fests — wirkt sofort an
  /// allen Kassen, ohne Neustart. Im internen Betrieb nur den Pfand.
  static Future<KasseEvent> updateActive({String? name, double? chipDeposit}) async {
    final json = await BackendCli.run([
      'event-update',
      if (name != null) ...['--name', name],
      if (chipDeposit != null) ...['--deposit', chipDeposit.toStringAsFixed(2)],
    ]);
    return KasseEvent.fromJson(json['event'] as Map<String, dynamic>);
  }

  static Future<void> end() => BackendCli.run(['event-end']);

  static Future<void> exportPreset(int eventId, String path) =>
      BackendCli.run(['preset-export', '$eventId', path]);

  /// Gibt die Anzahl exportierter Buchungen zurück.
  static Future<int> exportCsv(int eventId, String path, {int? periodId}) async {
    final json = await BackendCli.run([
      'csv-export',
      '$eventId',
      path,
      if (periodId != null) ...['--period', '$periodId'],
    ]);
    return json['rows'] as int;
  }
}
