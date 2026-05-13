# NFC-Kasse — Benutzerhandbuch

**Version 1.0 · Deutsch**

---

## Inhaltsverzeichnis

1. [Was ist NFC-Kasse?](#1-was-ist-nfc-kasse)
2. [Erste Schritte — Anmeldung](#2-erste-schritte--anmeldung)
3. [Die Benutzeroberfläche](#3-die-benutzeroberfläche)
4. [Mitarbeiter-Anleitung — Die Kasse bedienen](#4-mitarbeiter-anleitung--die-kasse-bedienen)
   - 4.1 [Gäste-Armband einscannen](#41-gäste-armband-einscannen)
   - 4.2 [Produkte in den Warenkorb legen](#42-produkte-in-den-warenkorb-legen)
   - 4.3 [Buchung abschließen](#43-buchung-abschließen)
   - 4.4 [Letzte Buchung stornieren](#44-letzte-buchung-stornieren)
   - 4.5 [Neuer Kunde](#45-neuer-kunde)
   - 4.6 [Guthaben reicht nicht aus](#46-guthaben-reicht-nicht-aus)
5. [Anleitung für Veranstaltungs-Verantwortliche](#5-anleitung-für-veranstaltungs-verantwortliche)
   - 5.1 [Statistiken einsehen](#51-statistiken-einsehen)
   - 5.2 [Unbegrenzte Stornierung](#52-unbegrenzte-stornierung)
6. [Admin-Anleitung — Einrichtung & Konfiguration](#6-admin-anleitung--einrichtung--konfiguration)
   - 6.1 [Erstinstallation](#61-erstinstallation)
   - 6.2 [Kategorien anlegen](#62-kategorien-anlegen)
   - 6.3 [Produkte anlegen](#63-produkte-anlegen)
   - 6.4 [Mitarbeiter-Konten verwalten](#64-mitarbeiter-konten-verwalten)
   - 6.5 [Bearbeitungsmodus — Produkte während des Events anpassen](#65-bearbeitungsmodus--produkte-während-des-events-anpassen)
   - 6.6 [Guthaben aufladen](#66-guthaben-aufladen)
   - 6.7 [Guthaben auszahlen](#67-guthaben-auszahlen)
   - 6.8 [Checkliste vor dem Event](#68-checkliste-vor-dem-event)
7. [Fehlerbehebung](#7-fehlerbehebung)

---

## 1. Was ist NFC-Kasse?

NFC-Kasse ist ein bargeldloses Kassensystem für Veranstaltungen. Gäste laden an der Bonkasse (Eingang) Guthaben auf ihre NFC-Armbänder. An den Ständen scannen Mitarbeiter das Armband und buchen Produkte — der Betrag wird automatisch vom Guthaben abgezogen.

An den Ständen wird kein Bargeld mehr benötigt. Das System läuft in einem lokalen WLAN; keine Internetverbindung erforderlich.

**Rollen im Überblick:**

| Rolle | Aufgabe |
|---|---|
| Bonkasse | Armbänder mit Bargeld aufladen |
| Standverkäufer | Armbänder einscannen und Produkte buchen |
| Veranstaltungs-Verantwortlicher | Wie Standverkäufer + jede Buchung stornieren + Statistiken einsehen |
| Administrator | Vollzugriff: Einrichtung, Benutzerverwaltung, Produktverwaltung |

---

## 2. Erste Schritte — Anmeldung

1. App auf dem Tablet oder Smartphone öffnen.
2. **Benutzername** und **Passwort** eingeben (vom Administrator mitgeteilt).
3. Auf **Anmelden** tippen.

Die App bleibt 24 Stunden angemeldet. Bei automatischer Abmeldung einfach erneut einloggen.

Manuell abmelden:
- Unten in der linken Seitenleiste auf den eigenen Namen tippen → **Abmelden**
- Oder: **Einstellungen** → **Abmelden**

---

## 3. Die Benutzeroberfläche

### Auf einem Tablet (breiter Bildschirm)

Die linke Seitenleiste ist immer sichtbar:

```
┌──────────────────────────────────────────┐
│ NFC Kasse         │  Hauptbereich        │
│                   │                      │
│ KATEGORIEN        │  (Kasse / Statistik  │
│  · Bar            │   / Einstellungen)   │
│  · Essen          │                      │
│                   │                      │
│ Statistik         │                      │
│ Einstellungen     │                      │
│ [Ihr Name]        │                      │
└──────────────────────────────────────────┘
```

### Auf einem Smartphone (schmaler Bildschirm)

Auf das **☰ Hamburger-Menü** (oben links) tippen, um die Navigationsleiste zu öffnen. Der Hauptbereich füllt den gesamten Bildschirm.

---

## 4. Mitarbeiter-Anleitung — Die Kasse bedienen

Der **Kassieren-Bildschirm (POS)** ist die Hauptansicht nach der Anmeldung.

### 4.1 Gäste-Armband einscannen

**Mit einem USB-HID-Lesegerät (Tablet mit angeschlossenem Scanner):**
1. In das Textfeld oben tippen (Hinweis: "UID eingeben oder USB-Lesegerät verwenden...").
2. Armband an das Lesegerät halten.
3. Das Gerät tippt die UID automatisch ein und drückt Enter.
4. Das Guthaben des Gastes wird sofort angezeigt.

**Mit nativem NFC (Android-Smartphone):**
1. Das Textfeld zeigt "NFC scannen oder UID eingeben..." mit einem NFC-Symbol.
2. Armband an die Rückseite des Smartphones halten.
3. Die App erkennt das Tag und lädt das Guthaben — kein Knopfdruck nötig.

Die UID bleibt im Eingabefeld sichtbar. Rechts (oder unten) erscheint das aktuelle Guthaben des Gastes.

### 4.2 Produkte in den Warenkorb legen

1. In der Seitenleiste eine Kategorie auswählen (z. B. "Bar").
2. Auf eine Produktkachel tippen — das Produkt wird in den Warenkorb gelegt.
3. Erneut antippen für weitere Einheiten (Menge erhöht sich automatisch).
4. Einzelnes Produkt entfernen: **×** neben dem Artikel tippen.
5. Ganzen Warenkorb leeren: **Leeren** im Warenkorb-Kopfbereich tippen.

Der Warenkorb zeigt immer:
- Jedes Produkt mit Menge und Preis
- **Gesamt:** — Gesamtbetrag der aktuellen Bestellung
- **Rest Guthaben:** — Guthaben des Gastes nach dem Kauf (rot bei negativem Wert)

### 4.3 Buchung abschließen

1. Prüfen, ob der richtige Gast eingelesen wurde (Guthaben im Panel kontrollieren).
2. Warenkorb prüfen.
3. Auf **✓ Buchen** tippen.

Das Guthaben wird sofort abgezogen. Der Warenkorb wird geleert, das neue Guthaben angezeigt. Der Knopf **Letzte Buchung stornieren** erscheint — siehe Abschnitt 4.4.

> Der **Buchen**-Knopf ist deaktiviert (grau), wenn:
> - Der Warenkorb leer ist
> - Kein Gast eingelesen ist
> - Das Guthaben nicht für den Einkauf ausreicht

### 4.4 Letzte Buchung stornieren

Es gibt ein **5-Minuten-Fenster** für die Stornierung der letzten Buchung.

1. Auf **↩ Letzte Buchung stornieren** tippen (unter dem Buchen-Knopf).
2. Ein Dialog zeigt die gebuchten Artikel, den Gesamtbetrag und die Buchungszeit.
3. Auf **Stornieren** tippen, um zu bestätigen.

Der vollständige Betrag wird dem Gäste-Guthaben gutgeschrieben. Der Storno-Knopf verschwindet nach erfolgreicher Stornierung.

> Nach 5 Minuten verweigert der Server die Stornierung. In diesem Fall einen Veranstaltungs-Verantwortlichen mit unbegrenztem Stornorecht hinzuziehen.

### 4.5 Neuer Kunde

Wenn ein Armband zum ersten Mal eingelesen wird, erscheint ein rotes **"Neuer Kunde"**-Badge und das Guthaben zeigt **0,00 €**.

Möglichkeiten:
- Gast zur Bonkasse schicken, um Guthaben aufzuladen, dann erneut scannen.
- Bei Barzahlung am Stand: Buchung trotzdem durchführen — das Guthaben wird negativ (Schulden). Die Bonkasse kann später ausgleichen.

### 4.6 Guthaben reicht nicht aus

Der **Buchen**-Knopf wird grau und inaktiv, wenn der Warenkorb-Betrag das Guthaben übersteigt. Das "Rest Guthaben" wird rot angezeigt.

Möglichkeiten:
- Einzelne Produkte aus dem Warenkorb entfernen.
- Gast bittet um Aufladung an der Bonkasse.

---

## 5. Anleitung für Veranstaltungs-Verantwortliche

### 5.1 Statistiken einsehen

In der Seitenleiste auf **Statistik** tippen.

**Übersicht-Tab:**
- Gesamtumsatz (Summe aller nicht stornierten Buchungen)
- Gesamtanzahl der Transaktionen
- Umsatz aufgeschlüsselt nach Kategorie

**Transaktionen-Tab:**
- Die 50 neuesten Transaktionen mit Produktname, NFC-UID, Uhrzeit und Preis
- Rückerstattungen und Pfandrückgaben werden farblich hervorgehoben

### 5.2 Unbegrenzte Stornierung

Veranstaltungs-Verantwortliche mit der Berechtigung `sales.booking.cancel_unlimited` können jede Buchung stornieren — unabhängig davon, wann sie getätigt wurde. Der Ablauf ist identisch wie bei Standverkäufern (Abschnitt 4.4), ohne das 5-Minuten-Limit.

---

## 6. Admin-Anleitung — Einrichtung & Konfiguration

### 6.1 Erstinstallation

1. Backend auf dem Thin Client (Fujitsu S920) starten:
   ```
   python init_db.py
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```
2. `http://localhost:8000/docs` im Browser öffnen und prüfen, ob der Server läuft.
3. Mit **admin / admin** einloggen.
4. **Admin-Passwort sofort ändern:**
   - Über die Swagger-UI: `PUT /api/users/1` mit `{ "password": "neues-passwort" }`

### 6.2 Kategorien anlegen

Kategorien sind die Tabs in der POS-Seitenleiste (z. B. "Bar", "Essen", "Bonkasse").

**Über die Flutter-App:**
1. Als Admin (oder Benutzer mit `categories.create`) einloggen.
2. Unten in der Kategorieliste auf **Neue Kategorie** tippen.
3. Namen eingeben und **Erstellen** antippen.
4. Die neue Kategorie wird automatisch ausgewählt.

**Über die Swagger-UI:**
```
POST /api/products/categories
{ "name": "Bar", "sort_order": 2 }
```

Umbenennen oder Reihenfolge ändern: Im Bearbeitungsmodus auf das **Stift-Symbol** neben dem Kategorienamen tippen, oder `PUT /api/products/categories/{id}` verwenden.

### 6.3 Produkte anlegen

**Über die Flutter-App (empfohlen):**
1. Die gewünschte Kategorie in der Seitenleiste öffnen.
2. **Bearbeitungsmodus** aktivieren (unten in der Seitenleiste).
3. Auf die **+**-Kachel im Produktraster tippen.
4. Name, Preis und ggf. Farbe eingeben.
5. **Speichern** antippen.

**Über die Swagger-UI:**
```
POST /api/products/
{
  "name": "Bier 0,5L",
  "price": 3.50,
  "category_id": 2,
  "sort_order": 1,
  "color": "#90CAF9"
}
```

**Hinweise:**
- **Negative Preise** sind erlaubt und sinnvoll: z. B. für Pfandrückgaben (`-2,00 €`) oder Aufladen-Produkte, die Guthaben erhöhen statt abziehen.
- **Farben** helfen dem Personal, Produkte schnell zu finden. Im App-Editor Farbpicker verwenden oder Hex-Code eingeben (`#RRGGBB`).
- **Produkt deaktivieren** entfernt es aus dem Raster, ohne die Buchungshistorie zu löschen.

### 6.4 Mitarbeiter-Konten verwalten

**Neuen Benutzer anlegen:**

Über die Flutter-App (Benutzer-Bildschirm, benötigt `users.create`) oder:
```
POST /api/users/
{ "username": "stand1", "password": "geheim123", "display_name": "Anna" }
```
Passwörter müssen mindestens 6 Zeichen lang sein.

**Berechtigungen vergeben:**

Am schnellsten per Rollenvorlage:
```
POST /api/users/{id}/apply-template/{template_id}
```

Vordefinierte Vorlagen:

| Vorlage | Enthaltene Berechtigungen |
|---|---|
| Standverkäufer | Buchen, 5-Minuten-Storno, Guthaben anzeigen, Kategorien anzeigen, Lokale Einstellungen |
| Veranstaltungs-Verantwortlicher | Alles obige + Aufladen, Auszahlen, unbegrenzt stornieren, Kategorien erstellen, Statistiken einsehen, Benutzer verwalten |

**Kategorie-Zugriff vergeben:**

Nach der Rollenvorlage konkrete Kategorien zuweisen:
```
PUT /api/users/{id}/categories
{
  "categories": [
    { "category_id": 2, "can_edit": false, "can_delete": false, "can_deactivate": true }
  ]
}
```

Ein Standverkäufer mit `categories.view`, aber ohne Kategorie-Zugriff, sieht eine leere Seitenleiste. Mindestens eine Kategorie zuweisen!

**Benutzer deaktivieren:**

```
DELETE /api/users/{id}
```
Setzt `active=0`. Der Benutzer kann sich nicht mehr einloggen; seine Buchungshistorie bleibt erhalten.

### 6.5 Bearbeitungsmodus — Produkte während des Events anpassen

**Bearbeitungsmodus** am unteren Ende der Seitenleiste aktivieren (nur auf dem POS-Bildschirm sichtbar, wenn entsprechende Rechte vorhanden).

Im Bearbeitungsmodus können Sie:
- **Neues Produkt hinzufügen** (+ Kachel antippen)
- **Bestehendes Produkt bearbeiten** (Kachel antippen)
  - Name, Preis, Farbe und Reihenfolge ändern
- **Produkt deaktivieren / reaktivieren** (Schalter im Bearbeitungsdialog)
- **Produkt löschen** (Papierkorb-Symbol, benötigt `can_delete`)
- **Kategorie umbenennen** (Stift-Symbol neben dem Kategorienamen)

Änderungen sind sofort für alle verbundenen Geräte sichtbar.

### 6.6 Guthaben aufladen

Das Aufladen erfolgt an der Bonkasse direkt über die API (die Flutter-App hat noch keinen Aufladen-Bildschirm):

```
POST /api/topup/
{
  "nfc_uid": "04ABCDEF",
  "amount": 20.00,
  "payment_method": "cash"
}
```
Die Antwort enthält das neue Guthaben.

### 6.7 Guthaben auszahlen

Am Ende des Events können Gäste ihr Restguthaben in bar zurückbekommen:

```
POST /api/topup/payout/{nfc_uid}
```

Das Guthaben wird auf 0,00 € gesetzt; die Auszahlung wird im Protokoll vermerkt.

### 6.8 Checkliste vor dem Event

- [ ] Admin-Passwort geändert
- [ ] Alle Kategorien angelegt und in der richtigen Reihenfolge
- [ ] Alle Produkte mit korrekten Preisen und Farben angelegt
- [ ] Produkte mit negativem Preis angelegt (Pfandrückgabe, Aufladen)
- [ ] Alle Mitarbeiter-Konten angelegt, mit richtigen Berechtigungen und Kategorie-Zugriffen
- [ ] Testbuchung auf mindestens einem Tablet erfolgreich durchgeführt
- [ ] Teststornierung erfolgreich durchgeführt
- [ ] Backup von `kasse.db` vor Veranstaltungsbeginn erstellt
- [ ] Alle Tablets mit WLAN "Kasse" verbunden
- [ ] App öffnet sich auf jedem Tablet und lädt Kategorien

---

## 7. Fehlerbehebung

**Die App zeigt "Connection refused" oder einen Netzwerkfehler**

- Prüfen, ob das Backend auf dem Thin Client läuft.
- Sicherstellen, dass das Tablet mit dem WLAN "Kasse" verbunden ist.
- In den Einstellungen die Server-URL prüfen. Sie sollte `http://192.168.1.1:8000` lauten (oder die tatsächliche IP des Thin Clients).

**NFC wird nicht erkannt (Smartphone)**

- NFC in den Android-Einstellungen aktivieren.
- Armband ruhig 1–2 Sekunden an die Rückseite des Smartphones halten.
- Manche Schutzhüllen blockieren NFC — Hülle abnehmen und erneut versuchen.

**USB-Lesegerät tippt die UID, aber nichts passiert**

- Zuerst in das Eingabefeld tippen, damit es den Fokus erhält.
- Sicherstellen, dass das Lesegerät nach der UID einen Zeilenumbruch (`\n`) sendet. Die meisten HID-Lesegeräte tun dies standardmäßig.

**"Buchen"-Knopf ist inaktiv, obwohl der Warenkorb gefüllt ist**

- Prüfen, ob ein Gast eingelesen wurde (Guthaben wird angezeigt). Falls nicht, zuerst einscannen.
- "Rest Guthaben" prüfen — wenn rot (negativ), ist der Knopf absichtlich deaktiviert. Artikel entfernen oder Gast auffordern aufzuladen.

**"Storno" schlägt fehl mit "Cancel window expired"**

- Das 5-Minuten-Fenster ist abgelaufen. Einen Veranstaltungs-Verantwortlichen mit unbegrenztem Stornorecht kontaktieren.

**Ein Produkt ist ausgegraut (deaktiviert)**

- Das Produkt wurde deaktiviert. Im Bearbeitungsmodus Produkt antippen und reaktivieren.

**Der Statistik-Bildschirm zeigt keine Daten**

- Sicherstellen, dass die Berechtigung `statistics.revenue` vorhanden ist. Administrator kontaktieren.
- Wenn das Event gerade erst begonnen hat, sind möglicherweise noch keine Transaktionen vorhanden.
