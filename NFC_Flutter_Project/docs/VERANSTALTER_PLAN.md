# Plan: Veranstalter-Modell (mandantenfähig, Cloud-vorbereitet)

Stand: 18. Oktober 2026 · umgesetzt, noch nicht committet (siehe Fortschritt)

## Ziel

Alles, was heute an einem Fest hängt, gehört künftig einem **Veranstalter**: Benutzer, Rechte, Kategorien, Artikel, Chips mit Guthaben, Feste und der interne Betrieb. Zwei Veranstalter auf demselben Server sind vollständig getrennte Kassen. Lokal arbeitet immer genau ein Veranstalter zur Zeit, nacheinander. Später in der Cloud laufen hunderte Veranstalter gleichzeitig in einer PostgreSQL-Datenbank. Jedes Gerät sieht dann nur die Daten seines Veranstalters.

Die Datenbank hat dafür schon die Tabelle `tenant` und `tenant_id` in `user`, `customer` und `event`. Der Veranstalter **ist** dieser Tenant. Es kommt keine neue Ebene dazu, die vorhandene wird zu Ende gebaut.

## Was wem gehört

| Daten | gehört heute | gehört künftig |
| --- | --- | --- |
| Benutzer | Veranstalter | Veranstalter (unverändert) |
| Globale Rechte | Fest (`user_permission.event_id`) | Veranstalter |
| Kategorien | Fest (`category.event_id`) | Veranstalter, pro Fest aktivierbar |
| Rechte pro Kategorie | Fest (`user_category_access.event_id`) | Veranstalter (hängen an der festen Kategorie) |
| Artikel | Fest (über die Kategorie) | Veranstalter, pro Fest aktivierbar |
| Chips und Guthaben | Veranstalter | Veranstalter (unverändert) |
| Feste und „Intern“ | Veranstalter | Veranstalter (unverändert) |
| Buchungen, Aufladungen, Perioden, Pager, Bons | Fest | Fest (unverändert) |
| Name und Pfand | Fest | Fest, live änderbar |
| Bon-Layout, Drucker, Lizenzen, Netzwerk | Server (`config.env`, `bon.yaml`) | Server (später in der Cloud pro Veranstalter) |

Buchungen behalten `event_id` und `price_at_sale`. Statistik und Abrechnung jedes Festes bleiben deshalb gleich, auch wenn sich ein Artikelpreis später ändert.

## Datenmodell

- `category`: `event_id` entfällt, dafür kommt `tenant_id`.
- Neue Tabelle `event_category (event_id, category_id, sort_order)` hält fest, welche Kategorien in einem Fest oder in „Intern“ aktiv sind und in welcher Reihenfolge.
- `product`: bekommt `tenant_id`, die Zuordnung zur Kategorie bleibt. Das bisherige `active` (vorübergehend nicht buchbar) bleibt global.
- Neue Tabelle `event_product (event_id, product_id)` hält fest, welche Artikel in einem Fest aktiv sind.
- `user_permission`: `event_id` entfällt.
- `user_category_access`: `event_id` entfällt.
- `event`: unverändert, `name` und `chip_deposit` sind live änderbar.
- Alles SQL bleibt so, dass es auch auf PostgreSQL läuft: keine SQLite-Sonderfunktionen in neuer Logik.

## Wie der Server den Veranstalter kennt

- Jede Anfrage hat den Veranstalter aus dem Login-Token (`user.tenant_id`). Jede Abfrage filtert danach. Das ist die Grundlage für die Cloud und gilt schon lokal.
- **Lokal** gibt es einen **aktiven Veranstalter**, den das Verwaltungstool festlegt. Anmelden können sich nur dessen Benutzer. Die Anmeldeseite bleibt dadurch wie heute, ohne Veranstalter-Auswahl.
- **Cloud (später)**: Der Benutzername ist pro Veranstalter eindeutig. Die Anmeldung bekommt deshalb zusätzlich eine Veranstalter-Kennung, etwa per Feld, Subdomain oder QR-Code beim Einrichten des Geräts. Das wird jetzt nur vorbereitet, nicht gebaut.
- Kundenanzeige, Leaderboard und Kiosk zeigen lokal den aktiven Veranstalter.

## Verwaltungstool

- **Neue Seite „Veranstalter“**: Veranstalter anlegen (mit Name und erstem Admin-Konto samt Passwort), umbenennen und als aktiven Veranstalter wählen.
- Ein Wechsel geht nur, wenn kein Fest läuft. Vorher wird automatisch gesichert. Alle Geräte werden abgemeldet.
- **Seite „Feste“** zeigt nur die Feste des aktiven Veranstalters.
  - Beim **Fest starten** sind Name und Pfand Pflicht, beide Felder sind leer vorbelegt.
  - Häkchen legen fest, welche Kategorien und Artikel im Fest aktiv sind. Vorbelegt ist die Auswahl des internen Betriebs oder des gewählten früheren Festes.
- **Seite „Konfiguration“**:
  - „Name der Veranstaltung“ und „Chip-Pfand“ ändern das laufende Fest sofort, nach einer Rückfrage „Gilt sofort für alle Kassen“.
  - Im internen Betrieb ist der Name ausgegraut, nur der Pfand ist änderbar.
  - Ein neuer Pfand gilt nur für Chips, die ab dann ausgegeben werden. Chips beim Gast behalten ihren bezahlten Pfand.
  - `EVENT_NAME` und `CHIP_DEPOSIT` in `config.env` entfallen.
- **Festvorlage** speichert die aktiven Kategorien und Artikel mit Preisen sowie die Bon-Einstellungen.
  - Der Import in denselben Veranstalter aktiviert die vorhandenen Kategorien und Artikel nach Namen.
  - Der Import in einen anderen Veranstalter legt fehlende Kategorien und Artikel an.

## Kasse (App)

- Die Kategorie- und Artikellisten zeigen nur, was im laufenden Fest aktiv ist.
- **Bearbeitungsmodus**: Am Stift einer Kategorie gibt es „In diesem Fest aktiv“, dafür braucht man das Recht „Kategorie deaktivieren“, das bisher nichts bewirkt.
- **Artikelverwaltung**:
  - Sie zeigt alle Artikel des Veranstalters mit einem Schalter „In diesem Fest aktiv“.
  - Neue Artikel sind automatisch im laufenden Fest aktiv.
  - Ein geänderter Preis gilt sofort in jedem Fest, in dem der Artikel aktiv ist. Alte Buchungen behalten ihren Preis.
- Die Rechtevergabe bleibt optisch gleich, gilt aber für alle Feste.

## Migration bestehender Datenbanken

1. Automatische Sicherung vor der Migration.
2. Gleichnamige Kategorien aus allen Festen werden zu einer zusammengeführt. Gleichnamige Artikel in derselben Kategorie ebenso.
3. Unterscheidet sich der Preis, gewinnt der Artikel aus dem zuletzt aktiven Fest. Alte Buchungen behalten ihren gebuchten Preis.
4. Jedes Fest bekommt in `event_category`/`event_product` genau die Kategorien und Artikel, die es vorher hatte.
5. Als Stand der Rechte gelten die Rechte des gerade laufenden Betriebs. Bei Kategorierechten werden die Zeilen der zusammengeführten Kategorien vereint, gesetzte Häkchen gewinnen.
6. Der bestehende einzige Tenant wird zum ersten Veranstalter, mit dem Namen aus `config.env` als Vorschlag.

## Phasen

1. **Rechte und Benutzer festunabhängig**: `user_permission` und `user_category_access` ohne `event_id`, Kopieren beim Festwechsel entfällt.
2. **Kategorien und Artikel festunabhängig**: neue Tabellen, Aktivierung pro Fest in App und Verwaltungstool, Vorlagen anpassen.
3. **Fest-Name und Pfand**: Pflichtfelder beim Start, live änderbar in der Konfiguration.
4. **Veranstalter**: Seite im Verwaltungstool, aktiver Veranstalter, Login und alle Abfragen strikt nach `tenant_id`, BAR-Chip pro Veranstalter.
5. **Tests und Doku**: Backend-Tests für Trennung der Veranstalter und die Migration, Anleitungen und CLAUDE.md.

Nach jeder Phase bleibt das System lauffähig. Die Builds (App, Admin-Tool, Setup) machst du selbst.

## Entscheidungen (18.10.2026)

1. **Bestand**: „Fest starten“ bekommt die Option „Bestände zurücksetzen (unbegrenzt)“.
2. **Chips**: getrennte Guthaben pro Veranstalter. Ein veranstalterübergreifender Chip-Pool kommt erst mit dem Cloud-Projekt und wird jetzt nicht berücksichtigt.
3. **Veranstalter-Wechsel**: nur ohne laufendes Fest, danach werden alle Geräte abgemeldet.

## Fortschritt

So weit ist die Umsetzung. Zum Weitermachen reicht „fortsetzen“: Die nächste offene Zeile ist der Einstieg.

| Phase | Stand | Notizen |
| --- | --- | --- |
| 1+2 Backend: Rechte, Kategorien, Artikel festunabhängig (Schema v3) | fertig | 134 Backend-Tests grün, neu: `test_v3_migration.py` (echte v2-Datenbank) und `test_catalog_per_event.py`. Admin-CLI: `event-start` mit `--reset-stock`/`--keep-stock` und `--categories`, `events` liefert `categories`. |
| 2 App: Kategorien und Artikel pro Fest aktivieren | fertig | Artikelverwaltung mit Schaltern „Im Fest“ (Kategorie: Recht „Kategorie deaktivieren“, Artikel: „Deaktivieren“). Kategorie-Dialog mit „In diesem Fest anzeigen“. Die Rechtevergabe zeigt alle Kategorien. `flutter analyze` ohne Befunde. Die 7 roten `formatters_test`-Tests waren schon vorher rot (Gebietsschema). Andere Geräte sehen ein Ein- oder Ausschalten erst beim nächsten Neuladen, also nach einem Festwechsel, einer Anmeldung oder einer abgelehnten Buchung. |
| 3 Fest-Name und Pfand | fertig | Backend: `event-update` (live, „Intern“ nur Pfand), `event-start --deposit` ist Pflicht, `EVENT_NAME`/`CHIP_DEPOSIT` aus config.py und der Vorlage entfernt (das erste Fest einer neuen Datenbank heißt „Hauptveranstaltung“ mit 0 € Pfand). Verwaltungstool: Fest-starten-Dialog mit Pflichtfeldern, Auswahl der Warengruppen und „Bestände zurücksetzen“. Konfiguration mit „Für alle übernehmen“ und Rückfrage. `flutter analyze` ohne Befunde, 138 Backend-Tests grün. Kassen zeigen einen geänderten Festnamen erst nach dem Neuladen. |
| 4 Veranstalter | fertig | Backend: `tenants.py` (anlegen, aktivieren, umbenennen, BAR-Chip pro Veranstalter). Anmeldung, Token-Erneuerung und `get_current_user` nur für den aktiven Veranstalter, ein Wechsel meldet alle Geräte sofort ab. Leaderboard, `/health` und Hilfe-WebSocket zeigen den aktiven Veranstalter. Admin-CLI: `tenants`, `tenant-create` (Passwort über stdin), `tenant-activate` (nur ohne Fest, Sicherung „vor-veranstalterwechsel“), `tenant-rename`. Verwaltungstool: neue Seite „Veranstalter“. Neu: `test_veranstalter.py`, damit 146 Backend-Tests grün. Kundenanzeige: Ihr Zustand liegt im Speicher und ist nach Benutzername geschlüsselt, das reicht lokal. Für die Cloud muss der Veranstalter in den Schlüssel. |
| 5 Tests und Doku | fertig | Bedieneranleitung (3.6 Veranstalter, 5.6 Was ein Fest zeigt, 6.6, 11.2), Handbuch (Sicherungsarten, config.env, Datenbank-Update), CLAUDE.md, README und Bilder-README angepasst. Wissensgraph per `graphify update .` aktualisiert. **Offen:** Builds (App, Verwaltungstool, Setup) und ein Test am echten Gerät durch Kim. PDF und Word der Anleitungen neu erzeugen. Neue Screenshots (Liste in der Bilder-README). |

## Technischer Entwurf (Schema v3)

Für die Weiterarbeit, falls die Sitzung abbricht.

- `db_backup.SCHEMA_VERSION = 3`. Frische Datenbanken legt `init_db.py` direkt in v3 an. Bestehende hebt `migrations.migrate_v3(db_path)` an: eigene Verbindung mit `PRAGMA foreign_keys=OFF`, Tabellen-Neubau nach dem offiziellen SQLite-Verfahren, am Ende `foreign_key_check`. Aufruf in `main._migrate()` nach `run_migrations()`. Die v2-Teile in `run_migrations()` (Intern-Bootstrap mit `user_permission.event_id`) laufen nur noch bei `user_version < 3`.
- Die v2-Struktur ist als `backend/tests/legacy_init_db_v2.py` eingefroren, damit die Migrationstests eine echte v2-Datenbank bauen können.
- Neue Struktur:
  - `category(id, tenant_id, name, sort_order, deleted)`
  - `event_category(event_id, category_id)`
  - `event_product(event_id, product_id)`: nur Basis-Artikel. Optionen folgen ihrem Basis-Artikel über `COALESCE(p.group_id, p.id)`.
  - `user_permission(user_id, permission_id, …)`
  - `user_category_access(user_id, category_id, 7 Flags, …)`
  - `tenant.active` für Phase 4
- `product.tenant_id` entfällt gegenüber dem Plan: Der Veranstalter ergibt sich eindeutig aus der Kategorie, doppelte Daten würden nur auseinanderlaufen.
- `product.active` (grau, nicht buchbar) bleibt global. Die Zugehörigkeit zum Fest steht in `event_product`. Die Reihenfolge der Kategorien ist global (`category.sort_order`), nicht pro Fest.
- Migration, Zusammenführung: gleichnamige Kategorien pro Veranstalter, gleichnamige Basis-Artikel pro Kategorie, Optionen pro (Basis, Name). Die Kanonische ist die aus dem laufenden Betrieb, sonst die mit der höchsten id. `sale.product_id`, `product.group_id/category_id` und die Präferenz-Schlüssel `layout.cat_<id>` bzw. `product.color.<id>` (samt id-Listen in den Layouts) werden umgehängt.
- Migration, Rechte:
  - Globale Rechte pro Benutzer aus dem laufenden Betrieb. Hat der Benutzer dort keine, aus „Intern“, sonst aus seinem letzten Fest.
  - Kategorierechte werden pro (Benutzer, Kategorie) per ODER zusammengeführt.
- Gemeinsame Hilfsfunktionen in `catalog.py` (Manager-Prüfung, Kategorierechte, Aktiv-im-Fest).
- API:
  - `GET /api/products/categories?all=true` liefert alle Kategorien des Veranstalters mit `active_in_event`.
  - `PATCH /api/products/categories/{id}/active` braucht `categories.deactivate`. Wird eine Kategorie zum ersten Mal in einem Fest aktiviert, werden alle ihre Artikel mit aktiviert.
  - `PATCH /api/products/{id}/event-active` braucht `can_deactivate_article`.
  - Neue Artikel und Kategorien sind automatisch im laufenden Fest aktiv.
  - Buchung und Bondruck prüfen Kategorie und Artikel gegen das Fest. Ist etwas nicht aktiv, kommt 409 `event_changed` mit eigener Meldung.
- Fest starten (`event_lifecycle.start_event`):
  - Die Aktivierung wird aus der Quelle kopiert (Intern oder ein früheres Fest), optional eingeschränkt auf ausgewählte Kategorien.
  - Eine Vorlage ordnet nach Namen zu und legt Fehlendes an. Bestehende Artikel werden nicht überschrieben.
  - `reset_stock` setzt den Bestand der aktivierten Artikel auf unbegrenzt.
  - Es werden keine Rechte mehr kopiert.
