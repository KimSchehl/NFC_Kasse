# NFC-Kasse – Bedieneranleitung

18. Oktober 2026 · Kim Schehl

## 1. Überblick

NFC-Kasse ist ein bargeldloses Kassensystem für Veranstaltungen. Jeder Gast bekommt einen NFC-Chip (Armband oder Karte), auf den an der Bonkasse Guthaben geladen wird. An den Ständen wird der Chip gescannt und der Betrag abgebucht. Ein Windows-Laptop im eigenen Netz ist der Server, kassiert wird auf Tablets, Smartphones oder im Browser. Während der Veranstaltung braucht das System kein Internet.

Diese Anleitung führt Schritt für Schritt durch Installation, Einrichtung, Verkauf und Abrechnung. Für einzelne Aufgaben gibt es eigene Anleitungen:

- [Kurzanleitung Standpersonal](Kurzanleitung_Standpersonal.md): eine Seite für die Leute am Stand. Chip scannen, Artikel antippen, buchen.
- [Zusatzfunktionen Pager und Leaderboard](Zusatzfunktionen_Pager_Leaderboard.md): die beiden Funktionen mit Lizenz.
- [Handbuch für Systemadministratoren](Handbuch_Systemadministratoren.md): Router, feste IP-Adressen, der Name nfc-kasse.lan, Datensicherung und Fehlersuche im Detail.

### Was zum System gehört

| Baustein | Aufgabe | Wo |
| --- | --- | --- |
| Server (NFC-Kasse Backend) | speichert Chips, Guthaben, Artikel und Buchungen | Windows-Dienst auf dem Server-Laptop, meist der Laptop an der Bonkasse |
| NFC-Kasse Verwaltung | Dienst starten und stoppen, Veranstalter wählen, Feste starten und beenden, Einstellungen, Bon-Layout, Datensicherung | Programm auf dem Server-Laptop |
| Kassen-App | kassieren, aufladen, auszahlen, Statistik | Android-Tablets und -Smartphones |
| Weboberfläche | dieselbe Kasse im Browser | `http://nfc-kasse.lan:8000/webapp` |
| NFC-Leser | liest den Chip | Bluetooth-Leser „NFC-Reader\_0001“ usw., eingebautes NFC (Android) oder USB-Leser |
| Bondrucker (optional) | druckt Papierbons für Barverkäufe | im Netzwerk (empfohlen) oder per Kabel am Server |
| Router mit WLAN | verbindet alle Geräte | z. B. GL.iNet |

### Was Sie brauchen

- Einen Windows-Laptop oder -PC (64 Bit) als Server. Für die Installation brauchen Sie Administratorrechte.
- Einen eigenen Router mit WLAN, in dem Server und alle Kassen sind. Wie der Router eingerichtet wird, steht im Handbuch für Systemadministratoren.
- Android-Tablets oder -Smartphones als Kassen. Für die Weboberfläche mit Bluetooth-Leser: Google Chrome oder Microsoft Edge.

### Adressen in dieser Anleitung

Die Anleitung geht von der Standard-Einrichtung aus. Der Server ist unter `http://nfc-kasse.lan:8000` erreichbar. Kennt Ihr Netz diesen Namen nicht, nehmen Sie überall stattdessen `http://192.168.1.2:8000`. Diese Adresse hat der Server-Laptop, wenn der Router nach dem Handbuch für Systemadministratoren eingerichtet ist.

## 2. Installation

Die Installation machen Sie einmal auf dem Server-Laptop. Danach läuft NFC-Kasse als Windows-Dienst: Er startet mit Windows von selbst und wird nach einem Absturz automatisch neu gestartet. Für den Download brauchen Sie einmal Internet, für den Betrieb nicht mehr.

### 2.1 Setup herunterladen

1. Am Server-Laptop im Browser **https://nfc-kasse.de/download** öffnen.
2. **NFC-Kasse-Setup.exe** herunterladen. Fragt der Browser, ob die Datei behalten werden soll, bestätigen Sie mit **Behalten**.

### 2.2 Installieren

1. Im Ordner **Downloads** doppelt auf **NFC-Kasse-Setup.exe** klicken.
2. Zeigt Windows „Der Computer wurde durch Windows geschützt“: auf **Weitere Informationen** und dann auf **Trotzdem ausführen** klicken. Die Meldung erscheint, weil das Setup nicht signiert ist.
3. Die Frage der Benutzerkontensteuerung mit **Ja** beantworten.
4. Seite **Installationsmodus**: Bei einer Neuinstallation ist **Installieren** vorgewählt. Auf **Weiter** klicken.
5. Zielordner `C:\Program Files\NFC-Kasse` so lassen, **Weiter**.
6. **Desktop-Symbol erstellen** ankreuzen. Das legt „NFC-Kasse öffnen“ und „NFC-Kasse Verwaltung“ auf den Desktop. **Weiter**.
7. **Installieren** klicken. Das Setup kopiert die Dateien, richtet den Dienst und die Firewall ein und startet den Dienst.
8. Auf der letzten Seite auf **Fertigstellen** klicken.
9. **NFC-Kasse Verwaltung** öffnen, Seite **Lizenzen** (Abschnitt 3.5). Den Lizenzschlüssel der Kasse eintragen und **Speichern & Dienst neu starten**. Ohne gültige Hauptlizenz startet der Dienst nicht.
10. Danach öffnet **NFC-Kasse öffnen** auf dem Desktop die Anmeldeseite der Kasse. Zeigt der Browser zunächst einen Fehler, ein paar Sekunden warten und die Seite neu laden.

Weiter geht es mit Abschnitt 4, Erster Start.

### 2.3 Was das Setup einrichtet

Das Setup legt das Programm in `C:\Program Files\NFC-Kasse\` und die Daten in `C:\ProgramData\NFC-Kasse\` ab. Es richtet den Windows-Dienst **NFC-Kasse Backend**, eine Firewall-Regel, die Browser-Einstellung für den Bluetooth-Leser und den Startmenü-Ordner **NFC-Kasse** ein. Die Einzelheiten stehen im Handbuch für Systemadministratoren, Abschnitt 5.2.

### 2.4 Prüfen, ob alles läuft

1. **NFC-Kasse Verwaltung** öffnen. Auf dem Dashboard muss „NFC-Kasse Backend: Läuft“ stehen (Abschnitt 3).
2. An einem Tablet im selben WLAN den Browser öffnen und `http://nfc-kasse.lan:8000/webapp` eingeben. Die Anmeldeseite muss erscheinen. Klappt das nur am Laptop selbst, hilft das Handbuch für Systemadministratoren weiter (Router und Firewall).
3. Den Laptop einmal neu starten und prüfen, ob der Dienst danach wieder läuft.

### 2.5 Android-App auf Tablets und Smartphones installieren

Die App kommt vom eigenen Server, nicht aus dem Play Store.

1. An einem Gerät, das schon angemeldet ist, zum Beispiel am Server-Laptop, **Einstellungen → Über** öffnen. Unten steht ein QR-Code.
2. Den QR-Code mit der Kamera des Tablets scannen. Alternativ im Browser des Tablets `http://nfc-kasse.lan:8000/download` eingeben.
3. Auf der Download-Seite **APK herunterladen** tippen.
4. Die Datei in den Downloads öffnen. Fragt Android nach, bei **Aus dieser Quelle erlauben** den Schalter einschalten und zurück.
5. **Installieren** tippen und die App öffnen.

![Einstellungen, Reiter Über: Server-Adresse, Version, Abmelden und QR-Code zum App-Download](../images/bedieneranleitung/app/tablet/22_einstellungen_ueber.png)

![Download-Seite auf dem Server mit dem Knopf „APK herunterladen“](../images/bedieneranleitung/app/tablet/31_app_download.png)

Neue Versionen bietet die App danach selbst an: Sie zeigt **Update verfügbar**, mit **Jetzt aktualisieren** wird die neue Version installiert.

### 2.6 Aktualisieren

1. Die neue **NFC-Kasse-Setup.exe** von https://nfc-kasse.de/download herunterladen.
2. Ausführen. Auf der Seite Installationsmodus ist jetzt **Aktualisieren** vorgewählt.
3. Durchklicken bis **Fertigstellen**. Das Setup stoppt den Dienst, ersetzt das Programm und startet den Dienst wieder.

Datenbank, Einstellungen und Bon-Layout bleiben dabei erhalten. Aktualisieren Sie nicht während des Verkaufs, für kurze Zeit sind keine Buchungen möglich.

### 2.7 Deinstallieren

1. In Windows **Einstellungen → Apps** den Eintrag **NFC-Kasse Backend** deinstallieren. Oder das Setup starten und **Deinstallieren** wählen.
2. Zuerst kommt die Frage „Sollen auch alle gespeicherten Daten gelöscht werden?“. **Nein** ist vorgewählt und behält Datenbank, Einstellungen und Sicherungen für eine spätere Neuinstallation. **Ja** löscht alles endgültig.
3. Die Rückfrage zur Deinstallation bestätigen.

## 3. Das Verwaltungstool

Mit der **NFC-Kasse Verwaltung** steuern Sie den Server am Laptop: Dienst starten und stoppen, Feste starten und beenden, Einstellungen ändern, den Bon gestalten, Daten sichern. Alles, was mit Artikeln, Benutzern und Verkauf zu tun hat, machen Sie dagegen in der Kasse selbst (ab Abschnitt 4). Das Verwaltungstool braucht keine Anmeldung: Wer den Server-Laptop bedient, darf alles.

### 3.1 Öffnen

1. Auf dem Desktop **NFC-Kasse Verwaltung** doppelklicken, oder im Startmenü unter **NFC-Kasse** wählen.
2. Die Frage der Benutzerkontensteuerung mit **Ja** beantworten.
3. Links sind acht Seiten: **Dashboard**, **Veranstalter** (Abschnitt 3.6), **Feste** (Abschnitt 11), **Konfiguration**, **Lizenzen** (Abschnitt 3.5), **Bon-Layout**, **Daten** (Abschnitt 11.6) und **Info**.

### 3.2 Dashboard

![Verwaltungstool, Dashboard: Dienst läuft, Knöpfe Starten, Stoppen, Neu starten und Schnellzugriff](../images/bedieneranleitung/windows/05_verwaltung_dashboard.png)

- **Dienst-Status** zeigt mit grünem Punkt „Läuft“ oder „Gestoppt“.
- **Starten**, **Stoppen**, **Neu starten** steuern den Dienst. Ausgegraut ist, was gerade nicht geht.
- **Server-Adresse** zeigt die Adresse, die ein Tablet im Feld Server-URL eintragen muss. Das Symbol daneben kopiert sie.
- **Weboberfläche öffnen** öffnet die Kasse im Browser dieses Laptops.
- **Protokolle öffnen** öffnet den Ordner mit den Protokolldateien. Den brauchen Sie nur bei Problemen.

Während der Dienst neu startet, sind für einige Sekunden keine Buchungen möglich. Die Kassen verbinden sich danach von selbst wieder.

### 3.3 Konfiguration

Hier stehen die Einstellungen des Servers. Ganz unten sind zwei Knöpfe:

- **Speichern & Dienst neu starten** speichert und übernimmt die Änderung sofort. Das ist der Normalfall.
- **Speichern** speichert nur. Die Änderung wirkt erst beim nächsten Neustart, die Verwaltung zeigt dann „Neustart nötig“.

![Konfiguration oben: Netzwerk, Veranstaltung und kostenpflichtige Zusatz-Features](../images/bedieneranleitung/windows/06_verwaltung_konfiguration.png)

| Feld | Was eintragen |
| --- | --- |
| Netzwerkschnittstelle (HOST) | `0.0.0.0` lassen. Damit ist der Server im ganzen Netz erreichbar. |
| Port | `8000` lassen. Wer ihn ändert, muss alle Adressen in dieser Anleitung anpassen. |
| Name der Veranstaltung, Chip-Pfand (€) | Name und Pfand des laufenden Festes. Diese beiden Felder haben einen eigenen Knopf **Für alle übernehmen**: Nach einer Rückfrage gelten sie sofort an allen Kassen und auf jedem neuen Bon, ohne Neustart. Ein neuer Pfand gilt für Chips, die ab dann ausgegeben werden, Chips beim Gast behalten ihren bezahlten Pfand. Im internen Betrieb heißt die Kasse immer „Intern“, dort ist nur der Pfand änderbar. |
| Virtuelle Bar-Chip-UID | `BAR` lassen. Auf diesen gedachten Chip werden Barverkäufe mit Papierbon gebucht. |

![Konfiguration Mitte: Lizenzschlüssel, Web-Zugriff und Beginn der Bondrucker-Einstellungen](../images/bedieneranleitung/windows/06b_verwaltung_konfiguration_lizenzen_web_drucker.png)

| Feld | Was eintragen |
| --- | --- |
| Webapp-Pfad | `/webapp` lassen. |
| Erlaubte Herkunfts-Adressen (CORS) | Empfohlen: `http://localhost:8000,http://127.0.0.1:8000,http://nfc-kasse.lan:8000,http://192.168.1.2:8000`. Dann klappt die Anmeldung im Browser unter beiden Adressen. |
| Protokoll-Level | `INFO` lassen. `DEBUG` nur zur Fehlersuche, das erzeugt sehr viele Einträge. |

![Konfiguration unten: Bondrucker und Bon-Inhalt](../images/bedieneranleitung/windows/06c_verwaltung_konfiguration_bondrucker_inhalt.png)

Die Bereiche **Bondrucker** und **Bon-Inhalt** sind in Abschnitt 8 Schritt für Schritt erklärt.

Wichtig beim Ausfüllen der übrigen Felder: Beträge mit Punkt schreiben, nicht mit Komma (`2.50`, nicht `2,50`). In Zahlenfelder wie Port oder Baudrate gehören nur Ziffern. Ein falscher Wert kann verhindern, dass der Dienst startet. Steht das Dashboard nach dem Speichern auf „Gestoppt“, korrigieren Sie den zuletzt geänderten Wert und speichern erneut.

### 3.4 Bon-Layout

![Verwaltungstool, Seite Bon-Layout mit Trennlinien, Artikelname und Leerzeilen](../images/bedieneranleitung/windows/07_verwaltung_bon_layout.png)

Hier legen Sie fest, wie der gedruckte Bon aussieht: Trennlinien, Trennzeichen, Schrift des Artikelnamens, Preis in derselben oder einer eigenen Zeile, Leerzeilen vor dem Abschneiden. Was auf dem Bon steht, stellen Sie dagegen unter Konfiguration → Bon-Inhalt ein. Die einzelnen Felder erklärt Abschnitt 8.5.

Diese Seite hat nur **Speichern**. Danach auf dem **Dashboard** auf **Neu starten** klicken, sonst druckt die Kasse weiter mit dem alten Layout.

### 3.5 Lizenzen und Info

Die Seite **Lizenzen** zeigt oben die **Installations-ID** dieser Installation. Darunter steht für jede Lizenz ein Feld für den Schlüssel:

- **Kasse (Hauptlizenz)**: Ohne gültigen Schlüssel startet der Dienst nicht.
- **Pager** und **Leaderboard**: die Zusatzfunktionen, jeweils mit dem Schalter **aktiviert**. Eine Funktion läuft nur mit eingeschaltetem Schalter und gültigem Schlüssel.

Unter jedem Feld zeigt die Kasse, ob der Schlüssel wirklich funktioniert: **Gültig** (mit Ablaufdatum, falls der Schlüssel eines hat), **Abgelaufen**, **Gehört zu einer anderen Installation**, **Schlüssel für eine andere Funktion**, **Ungültiger Schlüssel** (meist unvollständig kopiert) oder **Kein Schlüssel eingetragen**. Die Prüfung läuft schon beim Einfügen, vor dem Speichern.

So bekommen Sie einen Schlüssel:

1. Neben der Installations-ID auf das Kopier-Symbol klicken.
2. Eine Mail an **kontakt@nfc-kasse.de** schreiben (falls die nicht erreichbar ist: **info@nfc-kasse.de**), die Installations-ID einfügen und dazuschreiben, welche Lizenz Sie brauchen.
3. Den Schlüssel aus der Antwort in das passende Feld einfügen, bei Pager oder Leaderboard den Schalter **aktiviert** einschalten und **Speichern & Dienst neu starten** klicken.

Wie Pager und Leaderboard danach eingerichtet werden, steht in der Anleitung [Zusatzfunktionen Pager und Leaderboard](Zusatzfunktionen_Pager_Leaderboard.md).

![Verwaltungstool, Seite Info mit Version, Installations-ID und Ordnern](../images/bedieneranleitung/windows/07b_verwaltung_info.png)

Die Seite **Info** zeigt die Version des Verwaltungstools, die Installations-ID und die Ordner von Programm, Daten und Protokollen. Mit dem Symbol rechts kopieren Sie den jeweiligen Wert.

### 3.6 Veranstalter

Ein Server kann die Kassen mehrerer Veranstalter verwalten, zum Beispiel wenn er für verschiedene Vereine oder Weingüter im Einsatz ist. Jeder Veranstalter hat seine eigene, komplett getrennte Kasse: eigene Benutzer und Rechte, eigene Kategorien und Artikel, eigene Chips mit eigenem Guthaben und eigene Feste. In Betrieb ist immer genau einer. Nur dessen Benutzer können sich anmelden.

Bei der Installation gibt es einen Veranstalter „Lokal“. Für eine einzige Kasse brauchen Sie diese Seite nicht.

**Neuen Veranstalter anlegen**

1. Seite **Veranstalter** öffnen und auf **Neuer Veranstalter** klicken.
2. **Name** eingeben, dazu **Benutzername** und **Passwort** des ersten Administrators (mindestens 6 Zeichen, zweimal). Mit diesem Konto richtet der Veranstalter seine Kasse ein.
3. **Anlegen**. Der neue Veranstalter startet leer und im internen Betrieb.

**Zu einem anderen Veranstalter wechseln**

1. Beim laufenden Veranstalter muss das Fest beendet sein (Abschnitt 11.3).
2. Beim gewünschten Veranstalter auf **Aktivieren** klicken und die Rückfrage bestätigen.
3. Das Verwaltungstool sichert vorher automatisch. Danach sind alle Kassen abgemeldet. Jede meldet sich mit einem Konto des neuen Veranstalters wieder an.

Chips haben bei jedem Veranstalter ein eigenes Guthaben. Derselbe Chip ist beim anderen Veranstalter ein neuer Chip. Seiten **Feste** und **Konfiguration** (Name und Pfand) zeigen immer den Veranstalter in Betrieb. Umbenennen geht mit dem Stift neben dem Namen.

## 4. Erster Start der Kasse

Alles ab hier machen Sie in der Kasse, also in der App auf dem Tablet oder in der Weboberfläche im Browser. Beide sehen gleich aus und können dasselbe. Änderungen an Kategorien, Artikeln und Benutzern wirken sofort auf allen Geräten, ein Neustart ist dafür nicht nötig.

### 4.1 Anmelden

![Anmeldeseite mit Benutzername, Passwort und Server-URL](../images/bedieneranleitung/app/tablet/01_anmeldung.png)

1. Die App öffnen, oder im Browser `http://nfc-kasse.lan:8000/webapp` aufrufen.
2. Unten im Feld **Server-URL** steht bereits `http://nfc-kasse.lan:8000`. Wenn Sie ins Feld tippen, schlägt die App außerdem `http://192.168.1.2:8000` und früher benutzte Adressen vor. Klappt die Anmeldung mit dem Namen nicht, wählen Sie die Adresse mit der Zahl.
3. **Benutzername** und **Passwort** eingeben und auf **Anmelden** tippen.

Die Kasse bleibt angemeldet, auch nach einem Neustart des Geräts. Beim allerersten Mal melden Sie sich mit Benutzer **admin** und Passwort **admin** an.

### 4.2 Admin-Passwort ändern

Das machen Sie sofort nach der ersten Anmeldung, sonst kann sich jeder mit admin/admin anmelden.

1. In der Seitenleiste auf **Benutzer** tippen.
2. Beim Eintrag **Administrator** rechts auf den Stift tippen.
3. Im Feld **Neues Passwort** das neue Passwort eingeben, mindestens 6 Zeichen.
4. **Speichern**.

### 4.3 Die Oberfläche

![Kassenansicht auf dem Tablet: Seitenleiste links, Chip-Feld und Artikel in der Mitte, Warenkorb rechts](../images/bedieneranleitung/app/tablet/02_kasse_leer.png)

- **Seitenleiste links**: oben die **Kategorien** und **Neue Kategorie**, unten **Statistik**, **Benutzer**, **Protokolle**, **Artikelverwaltung**, **Einstellungen**, in der Kasse außerdem **Bearbeitungsmodus**. Ganz unten steht der Name des angemeldeten Benutzers. Jeder sieht nur, was er darf.
- **Mitte**: oben das Chip-Feld, darunter die Artikel als Kacheln.
- **Rechts**: das Guthaben des gescannten Chips, der Warenkorb und der Knopf **Buchen**. Den Trennbalken zwischen Kacheln und Warenkorb können Sie verschieben.
- **Oben rechts**: der rote Knopf **HILFE** und ein Symbol für die Verbindung zum Server. Ist ein Bluetooth-Leser gekoppelt, steht daneben ein zweites Symbol für den Leser.

Auf dem Smartphone ist die Seitenleiste eingeklappt. Sie öffnet sich mit dem Menü-Symbol oben links, der Warenkorb steht unter den Kacheln.

![Geöffnetes Menü auf dem Smartphone](../images/bedieneranleitung/app/handy/02b_menue_handy.png)

## 5. Kategorien und Artikel

Kategorien sind die Gruppen in der Seitenleiste, meist eine pro Stand, zum Beispiel „Bonkasse“, „Bar“ und „Essen“. Artikel sind die Kacheln, die an der Kasse angetippt werden. Welche Kategorien ein Mitarbeiter sieht, legen Sie in Abschnitt 6 fest.

Kategorien und Artikel legen Sie einmal an, sie bleiben über alle Feste erhalten. Pro Fest entscheiden Sie nur, welche davon die Kassen zeigen (Abschnitt 5.6). So haben Sie zum Beispiel einen festen Stamm von Kategorien und schalten für jedes Fest die passenden ein. Preis, Bestand und Farbe eines Artikels sind in jedem Fest gleich.

### 5.1 Kategorie anlegen

1. In der Seitenleiste unter den Kategorien auf **Neue Kategorie** tippen.
2. Den Namen eingeben und auf **Erstellen** tippen.

![Dialog „Neue Kategorie“](../images/bedieneranleitung/app/tablet/11_neue_kategorie.png)

Eine neue Kategorie ist im laufenden Fest sofort eingeschaltet.

Umbenennen, ausblenden oder löschen: In der Kasse unten in der Seitenleiste **Bearbeitungsmodus** einschalten. Neben jeder Kategorie erscheint ein Stift. Antippen, Namen ändern und speichern, mit **In diesem Fest anzeigen** für dieses Fest ausblenden (Recht „Kategorie deaktivieren“) oder die Kategorie löschen (Recht „Kategorie löschen“). Gelöscht ist sie in allen Festen.

Tipp: Legen Sie für die Bonkasse eine eigene Kategorie an. Dort liegen die Aufladeartikel und der Auszahlungs-Artikel, und nur das Personal der Bonkasse bekommt Zugriff darauf.

### 5.2 Artikel anlegen

1. In der Seitenleiste auf **Artikelverwaltung** tippen. Jede Kategorie erscheint als eigene Karte mit ihren Artikeln.
2. Bei der gewünschten Kategorie rechts auf **+ Neuer Artikel** tippen.
3. **Name** eingeben, so wie er auf der Kachel stehen soll, zum Beispiel „Bier 0,5 l“.
4. **Preis (€)** eingeben, mit Punkt: `4.00`.
5. Bei Bedarf weitere Felder ausfüllen (Tabelle unten).
6. **Speichern**. Die Kachel erscheint sofort auf allen Kassen dieser Kategorie. Ein neuer Artikel ist im laufenden Fest eingeschaltet.

![Artikelverwaltung mit den Kategorien Bonkasse und Bar und dem Knopf „Neuer Artikel“](../images/bedieneranleitung/app/tablet/13_artikelverwaltung.png)

![Dialog „Neuer Artikel“ mit allen Feldern](../images/bedieneranleitung/app/dialoge/artikel_neu.png)

| Feld | Wofür |
| --- | --- |
| Name | Beschriftung der Kachel und Name auf dem Bon. |
| Preis (€) | Verkaufspreis. Ein negativer Preis ist eine Gutschrift für den Gast und braucht beim Buchen das Recht **Aufladen** (Abschnitt 6.2). Für Becherpfand nehmen Sie deshalb einen Pfand-Artikel. |
| Guthaben Aufladung | Macht den Artikel zum Aufladeartikel. Das Preisfeld heißt dann **Auflade-Betrag (€)**, dort tragen Sie den Betrag positiv ein, z. B. `10`. Aufladungen zählen automatisch nicht zum Umsatz. Buchen darf sie nur, wer das Recht **Aufladen** hat. |
| Pfand-Artikel | Für Becher- oder Flaschenpfand: „Pfand +“ mit positivem Preis, „Pfand −“ mit negativem Preis. Pfand-Artikel zählen nicht zum Umsatz und brauchen kein Recht Aufladen. |
| Auszahlungs-Artikel | Zahlt beim Buchen das ganze Restguthaben plus Chip-Pfand aus. Als Preis `0` eintragen. Ein solcher Artikel reicht pro Bonkasse. Buchen darf ihn nur, wer das Recht **Auszahlen** hat. |
| Von Statistik ausschließen | Der Artikel zählt nicht zum Umsatz. |
| Bestand (leer = unbegrenzt) | Anzahl, die verkauft werden kann. Jede Buchung zählt herunter. Ab 10 Stück warnt die Kasse beim Buchen, bei 0 ist die Kachel rot-weiß umrandet und nicht mehr buchbar. |
| Aktiv (buchbar) | Erscheint erst beim Bearbeiten und nur mit dem Recht Deaktivieren. Ausgeschaltet bleibt die Kachel grau sichtbar, kann aber nicht gebucht werden. |
| Standard-Farbe | Farbe der Kachel auf allen Kassen. Jedes Konto kann sie für sich selbst umfärben (Abschnitt 5.5). Das erste Feld bedeutet „keine Farbe“. |
| Leaderboard-Punkte, Pager erforderlich | Nur sichtbar, wenn die Zusatzfunktion freigeschaltet ist. Erklärt in der Anleitung Zusatzfunktionen. |

Für die Bonkasse bewähren sich die Aufladeartikel „Aufladen 5 €“, „10 €“, „20 €“ und „50 €“ plus ein Auszahlungs-Artikel „Auszahlung“.

### 5.3 Artikel mit Optionen

Optionen sind Varianten eines Artikels mit eigenem Preis, zum Beispiel Currywurst „pur“ für 4,50 € und „mit Pommes“ für 7,00 €. An der Kasse gibt es dafür nur eine Kachel, beim Antippen erscheint die Auswahl.

1. In der **Artikelverwaltung** bei der Kategorie **+ Neuer Artikel** tippen.
2. **Name** eingeben, zum Beispiel „Currywurst“.
3. Ganz unten bei **Optionen** auf **+ Option hinzufügen** tippen.
4. Bei **Zusatz** den Text der Variante eingeben, zum Beispiel „mit Pommes“, und bei **Preis (€)** deren Preis, zum Beispiel `7.00`.
5. Für jede weitere Variante wieder **+ Option hinzufügen**, zum Beispiel „pur“ für `4.50`.
6. **Speichern**.

![Artikel „Currywurst“ mit der Option „mit Pommes“ und Preis 7.00, darunter die Button-Farben](../images/bedieneranleitung/app/dialoge/artikel_mit_optionen.png)

Wichtig:

- Sobald ein Artikel Optionen hat, verschwindet sein eigenes Preisfeld („Preis wird pro Option unten festgelegt“). Gebucht wird immer eine Option. Soll es die Currywurst auch ohne Beilage geben, braucht sie dazu eine eigene Option wie „pur“.
- Im Warenkorb und auf dem Bon steht der volle Name, zum Beispiel „Currywurst mit Pommes“.
- Optionen teilen sich Bestand, Leaderboard-Punkte und Pager mit ihrem Artikel.
- Eine Option entfernen Sie mit dem Mülleimer-Symbol neben ihr.

So sieht das an der Kasse aus: Kachel **Currywurst** antippen, dann die gewünschte Option. Mit **Schließen** wird nichts in den Warenkorb gelegt.

![Auswahlfenster „Currywurst“ an der Kasse mit der Option „mit Pommes“](../images/bedieneranleitung/app/tablet/08_optionen_auswahl.png)

### 5.4 Artikel ändern, verschieben, löschen

- **Ändern**: In der Artikelverwaltung den Artikel antippen, ändern, **Speichern**. Ein neuer Preis gilt nur für neue Buchungen, dann aber in jedem Fest, in dem der Artikel eingeschaltet ist.
- **In eine andere Kategorie verschieben**: Den Artikel lange drücken und auf die Karte der anderen Kategorie ziehen.
- **Löschen**: Im Dialog unten links **Löschen**. Artikel, die schon verkauft wurden, besser mit **Aktiv (buchbar)** ausschalten. Dann bleiben sie für die Auswertung erkennbar und lassen sich später wieder einschalten.

### 5.5 Kacheln anordnen und Bestand nachfüllen

1. In der Kasse unten in der Seitenleiste **Bearbeitungsmodus** tippen.
2. Eine Kachel lange drücken und an die neue Stelle ziehen.
3. Mit den runden Knöpfen unten rechts fügen Sie eine leere Position ein oder entfernen die letzte wieder. So lassen sich Gruppen bilden, zum Beispiel alle alkoholfreien Getränke in einer Reihe.
4. Eine Kachel antippen öffnet ein kleines Fenster für **Farbe** und **Bestand**, praktisch zum Nachfüllen während des Betriebs.
5. Zum Beenden wieder auf **Bearbeitungsmodus** tippen.

![Kasse im Bearbeitungsmodus: Stifte neben den Kategorien, Knöpfe für leere Positionen unten rechts](../images/bedieneranleitung/app/tablet/10_bearbeitungsmodus.png)

Anordnung und eigene Farbe der Kacheln speichert die Kasse für das Benutzerkonto, mit dem Sie sie ändern, getrennt für Hoch- und Querformat. Sie gelten auf jedem Gerät, an dem sich dieses Konto anmeldet, andere Konten sehen ihre eigene Anordnung. Richten Sie die Kacheln deshalb mit dem Konto ein, das später am Stand kassiert. Der Bestand gilt dagegen für alle Kassen.

### 5.6 Was ein Fest zeigt

Die **Artikelverwaltung** zeigt alle Kategorien und Artikel, auch die, die im laufenden Fest ausgeblendet sind. Ausgeblendete stehen grau mit dem Zusatz „nicht in diesem Fest“.

- Der Schalter **Im Fest** neben einer Kategorie blendet sie für das laufende Fest ein oder aus. Dafür braucht es das Recht „Kategorie deaktivieren“. Wird eine Kategorie zum ersten Mal in einem Fest eingeschaltet, kommen alle ihre Artikel mit.
- Der Schalter neben einem Artikel blendet ihn für das laufende Fest ein oder aus, mit seinen Optionen. Dafür braucht es in der Kategorie das Recht „Deaktivieren“.
- Ausgeblendet heißt: nicht in der Kasse und nicht buchbar. Anders als **Aktiv (buchbar)** im Artikel-Dialog: Ein inaktiver Artikel steht grau in der Kasse, zum Beispiel wenn er ausverkauft ist, und das in jedem Fest.

Welche Kategorien ein neues Fest zeigt, wählen Sie beim Start im Verwaltungstool (Abschnitt 11.2). Andere Kassen sehen ein Ein- oder Ausblenden spätestens nach dem nächsten Neuladen, zum Beispiel nach einer Anmeldung.

## 6. Mitarbeiter-Konten und Rechte

Jede Person, die kassiert, bekommt ein eigenes Konto. So sieht sie nur ihre Kategorien, und in der Auswertung ist erkennbar, wer was gebucht hat. Rechte gibt es auf zwei Ebenen: **globale Berechtigungen** für Aufgaben außerhalb der Kasse und **Rechte pro Kategorie** für Buchen, Storno und Artikel. Konten und Rechte gelten in jedem Fest (Abschnitt 6.6).

### 6.1 Konto anlegen

1. In der Seitenleiste auf **Benutzer** tippen, dann oben rechts auf **Neu**.
2. **Benutzername** eingeben, mit dem sich die Person anmeldet, zum Beispiel „anna“.
3. Optional einen **Anzeigenamen**, zum Beispiel „Anna (Bar)“. Er erscheint in der Seitenleiste und auf gedruckten Bons.
4. Ein **Passwort** mit mindestens 6 Zeichen vergeben.
5. Unter **Globale Berechtigungen** ankreuzen, was die Person außerhalb der Kasse darf (Tabelle 6.2). Für normales Standpersonal bleibt hier alles leer.
6. Unter **Kategorien & Berechtigungen** bei jeder Kategorie, an der die Person arbeitet, die Rechte setzen (Abschnitt 6.3).
7. **Speichern**.

![Benutzerliste mit Administrator, Anna (Bar), Bonkasse und Kiosk](../images/bedieneranleitung/app/tablet/15_benutzerliste.png)

![Dialog „Benutzer bearbeiten“ mit Benutzername, Anzeigename, Passwort, Aktiv und den globalen Berechtigungen](../images/bedieneranleitung/app/tablet/16_benutzer_bearbeiten.png)

### 6.2 Globale Berechtigungen

| Gruppe | Häkchen | Wirkung |
| --- | --- | --- |
| Guthaben | Aufladen | Aufladeartikel buchen (Artikel mit „Guthaben Aufladung“, Abschnitt 9.4). Zusätzlich braucht die Person **Buchen** in der Kategorie, in der der Aufladeartikel liegt. |
|  | Auszahlen | Den Auszahlungs-Artikel buchen (Abschnitt 9.6). Dafür ist kein Recht pro Kategorie nötig. |
| Kategorien | Kategorie erstellen, bearbeiten, deaktivieren, löschen | Wer auch nur eines davon hat, gilt als **Verantwortlicher**: Er sieht alle Kategorien, darf dort buchen, unbegrenzt stornieren und alle Artikel verwalten. |
| Statistik & Finanzen | Umsatz einsehen | Statistik mit den Reitern Übersicht und Chips, Tagesabschluss (Abschnitt 10 und 11.1) |
|  | Transaktionen einsehen | Reiter Transaktionen in der Statistik |
| Benutzerverwaltung | Benutzer anzeigen, erstellen, bearbeiten, deaktivieren, löschen | Konten verwalten wie in diesem Abschnitt |
|  | Rechte vergeben | Rechte anderer Konten ändern. Erst mit diesem Häkchen erscheint **Benutzer** in der Seitenleiste, dazu gehört meist **Benutzer anzeigen**. |
| Notfall | Notfall-Kontakt | Bekommt die Hilfe-Anfragen der Kassen (Abschnitt 9.8) |
| Bon-Druck | Bon drucken | Darf ohne Chip verkaufen und Papierbons drucken (Abschnitt 8.6) |
| Kundenterminal | Kiosk-Modus | Hat ein Konto nur dieses eine Häkchen und keine Kategorie, zeigt es nur die Guthaben-Abfrage für Gäste (Abschnitt 12.4). Bei einem Konto mit weiteren Rechten wirkt es nicht. |
| Protokolle | Protokolle einsehen | Menüpunkt **Protokolle** mit den Protokollen aller Geräte |
|  | Protokoll-Level verwalten | Im selben Menüpunkt festlegen, wie ausführlich jedes Gerät protokolliert |

Für Feste, Festvorlagen, die Abrechnung als CSV und Datensicherungen gibt es kein Recht in der Kasse. Das alles geht nur im Verwaltungstool am Server-Laptop (Abschnitt 11).

Das letzte aktive Konto mit **Rechte vergeben** lässt sich nicht deaktivieren oder löschen. So kann sich niemand aus der Rechteverwaltung aussperren.

### 6.3 Rechte pro Kategorie

Unter **Kategorien & Berechtigungen** steht jede Kategorie mit einem aufklappbaren Baum:

- **Buchungen → Buchen**: Die Person darf in dieser Kategorie verkaufen.
- **Buchungen → Storno** mit **5 min** oder **Unbegrenzt**: Mit „5 min“ darf die Person eine Buchung nur in den ersten fünf Minuten zurücknehmen, mit „Unbegrenzt“ jederzeit. Es gilt immer nur eins von beiden.
- **Positionen → Erstellen, Bearbeiten, Deaktivieren, Löschen**: Artikel dieser Kategorie verwalten (Abschnitt 5). Wer **Deaktivieren** hat, sieht auch die ausgeschalteten Artikel.

Die Kategorie erscheint in der Seitenleiste, sobald die Person dort mindestens ein Recht hat. Ohne jedes Recht bleibt sie unsichtbar. Ein Häkchen an der Kategorie selbst setzt oder entfernt alle Rechte darunter auf einmal.

Verantwortliche (Abschnitt 6.2) brauchen hier nichts, sie haben in jeder Kategorie alle Rechte.

### 6.4 Bewährte Einstellungen

| Rolle | Globale Berechtigungen | Rechte pro Kategorie |
| --- | --- | --- |
| Standpersonal, z. B. Bar | keine | Bar: Buchen, Storno 5 min |
| Bonkasse | Aufladen, Auszahlen, bei Barverkauf mit Bon zusätzlich Bon drucken | Bonkasse: Buchen, Storno 5 min |
| Schichtleitung | Kategorie bearbeiten, Umsatz einsehen, Notfall-Kontakt, bei Bedarf Aufladen und Auszahlen | keine nötig, sieht als Verantwortliche alles |
| Gäste-Terminal | nur Kiosk-Modus | keine |

Ein Gerät, an dem sich alle Leute eines Standes abwechseln, kann auch mit einem gemeinsamen Konto pro Stand laufen, zum Beispiel „bar“. Dann ist in der Auswertung aber nicht mehr erkennbar, wer gebucht hat.

### 6.5 Passwort ändern, Konto sperren

- **Passwort ändern**: Benutzer → Stift beim Konto → **Neues Passwort** eingeben → **Speichern**. Leer lassen bedeutet: unverändert.
- **Konto sperren**: Das Häkchen **Aktiv** entfernen. Die Person kann sich nicht mehr anmelden, ihre Buchungen bleiben in der Auswertung erhalten. Das ist besser als Löschen.

### 6.6 Rechte und Feste

Konten, globale Berechtigungen und Rechte pro Kategorie gehören dem Veranstalter, nicht einem Fest. Sie gelten unverändert im internen Betrieb und in jedem Fest, auch in künftigen. Eine Änderung während eines Festes bleibt nach dem Fest erhalten.

Unter **Kategorien & Berechtigungen** stehen alle Kategorien, auch die, die das laufende Fest ausblendet. Sie tragen den Zusatz „nicht in diesem Fest“. So lassen sich Rechte schon für das nächste Fest vergeben.

## 7. Bluetooth-NFC-Leser verbinden

Der NFC-Leser ist ein kleines Gerät mit Akku. Er liest den Chip und schickt dessen Nummer per Bluetooth an die Kasse. Er hat nur zwei Bedienelemente: einen **Schiebeschalter** zum Ein- und Ausschalten und eine **USB-C-Buchse** zum Laden. Auf der Rückseite steht sein Name, zum Beispiel **NFC-Reader\_0001**. Am Leser selbst müssen Sie nichts einstellen.

Jeder Leser gehört zu genau einer Kasse. Kleben Sie am besten die Nummer des Lesers auch auf das passende Tablet.

### 7.1 Laden

1. Ein USB-C-Kabel an die Buchse des Lesers stecken, das andere Ende an ein USB-Netzteil oder an den Laptop.
2. Vor jeder Veranstaltung voll laden. Den Akkustand zeigt die Kasse an, sobald der Leser verbunden ist.
3. Nach der Veranstaltung den Leser mit dem Schiebeschalter ausschalten.

### 7.2 Mit der Android-App verbinden

1. Den Leser mit dem Schiebeschalter einschalten.
2. Am Tablet Bluetooth einschalten. Den Leser **nicht** in den Bluetooth-Einstellungen von Android koppeln, das erledigt die App.
3. In der App **Einstellungen** öffnen, Reiter **NFC-Lesegerät**.
4. Auf **Nach Geräten suchen** tippen.
5. Beim ersten Mal fragt Android nach der Berechtigung **Geräte in der Nähe**, bei älteren Geräten nach dem **Standort**. Erlauben.
6. Die Liste zeigt alle eingeschalteten Leser in Reichweite mit Namen und Signalstärke. Den Leser antippen, dessen Name auf der Rückseite steht.
7. Unter **Gekoppeltes Lesegerät** steht jetzt „Verbunden · Akku … %“. Fertig.

![Einstellungen, Reiter NFC-Lesegerät: noch kein Leser gekoppelt, Knopf „Nach Geräten suchen“](../images/bedieneranleitung/app/tablet/24_einstellungen_nfc_lesegeraet.png)

Liegen mehrere Leser nebeneinander, hilft die Signalstärke: Der Wert näher an null gehört zum nächsten Leser, „−45 dBm“ ist also näher als „−80 dBm“.

Die App merkt sich den Leser. Beim nächsten Start und nach einem kurzen Abbruch, etwa wenn der Leser aus- und wieder eingeschaltet wurde, verbindet sie sich von selbst wieder.

### 7.3 Im Browser verbinden

In der Weboberfläche funktioniert der Leser mit **Google Chrome** und **Microsoft Edge**, nicht mit Firefox oder Safari. Auf dem Server-Laptop hat das Setup alles vorbereitet. Auf jedem anderen PC muss die Adresse der Kasse einmal im Browser als vertrauenswürdig eingetragen werden. Wie das geht, steht im Handbuch für Systemadministratoren, Abschnitt 8.

1. Den Leser einschalten. Am PC Bluetooth einschalten: Windows **Einstellungen → Bluetooth und Geräte → Bluetooth** auf Ein. Den Leser nicht in Windows koppeln.
2. In der Kasse **Einstellungen → NFC-Lesegerät → Nach Geräten suchen**.
3. Der Browser öffnet ein eigenes Fenster mit den gefundenen Lesern. Den richtigen Leser wählen und auf **Koppeln** klicken.
4. Der Leser erscheint danach in der Liste der Kasse. Antippen, bis „Verbunden“ erscheint.

Zwei Einschränkungen des Browsers sind normal:

- Nach jedem Neuladen der Seite steht der Leser auf „Getrennt“. Dann im Menü neben dem Leser **Verbinden** wählen und im Fenster des Browsers erneut bestätigen.
- Wird der Leser ausgeschaltet oder ist er außer Reichweite, merkt die Kasse das erst nach bis zu 90 Sekunden.

### 7.4 Status und Menü

- Ein Symbol oben rechts, neben dem Symbol für den Server, zeigt jederzeit, ob der Leser verbunden ist.
- Im Menü neben dem gekoppelten Leser stehen **Verbinden**, **Trennen** und **Entkoppeln**. Mit **Entkoppeln** vergisst die Kasse den Leser. Das brauchen Sie, wenn ein anderer Leser an diese Kasse soll.

### 7.5 Andere Wege, den Chip zu lesen

- **Eingebautes NFC (Android)**: Den Chip an die Rückseite des Tablets halten. NFC muss in den Android-Einstellungen eingeschaltet sein.
- **USB-Leser**: Er tippt die Nummer wie eine Tastatur ein. Vorher einmal ins Chip-Feld tippen, damit es aktiv ist.
- **Von Hand**: Die Chip-Nummer ins Chip-Feld tippen und mit Enter oder dem Pfeil rechts bestätigen.

## 8. Bondrucker einrichten und Bon gestalten

Der Bondrucker ist optional. Er ist für Gäste gedacht, die keinen Chip möchten: Sie zahlen an der Bonkasse bar und bekommen für jeden Artikel einen Papierbon, den sie am Stand einlösen. Gedruckt wird über den Server, deshalb kann jede Kasse Bons drucken, auch ein Smartphone.

### 8.1 Welcher Drucker?

NFC-Kasse ist an kein bestimmtes Modell gebunden. Geeignet ist jeder Bondrucker (Thermodrucker) mit dem Standard ESC/POS, für 80-mm- oder 58-mm-Papier. Empfohlen sind Drucker mit **Netzwerkanschluss (LAN)**: Sie können überall im Netz stehen, und es gibt keine Probleme mit Treibern oder COM-Ports.

Diese Modelle wurden getestet:

| Modell | Anschluss | Einstellungen |
| --- | --- | --- |
| Epson TM-T88II | seriell, am Laptop über einen USB-Seriell-Adapter | 80 mm, 42 Zeichen pro Zeile, 9600 Baud, mit Abschneider |
| Zweites getestetes Modell (Angabe folgt) |  |  |

### 8.2 Netzwerkdrucker einrichten (empfohlen)

1. Den Drucker mit einem LAN-Kabel an den Router anschließen und einschalten.
2. Einen Selbsttest drucken. Bei den meisten Modellen hält man dazu die Vorschub-Taste beim Einschalten gedrückt. Der Ausdruck zeigt die IP-Adresse des Druckers.
3. Im Router eine feste Adresse für den Drucker einrichten, üblich ist `192.168.1.3`. Das beschreibt das Handbuch für Systemadministratoren in Abschnitt 2.3 und 9.1.
4. Am Server-Laptop das Verwaltungstool öffnen, Seite **Konfiguration**, Bereich **Bondrucker**.
5. **Anschlussart** auf `network` stellen. Die Felder ändern sich dann.
6. **TCP-Port**: `9100`. **Drucker-IP-Adresse**: die Adresse aus Schritt 3, zum Beispiel `192.168.1.3`.
7. **Zeichen pro Zeile**: `42` bei 80-mm-Papier, meist `32` bei 58-mm-Papier.
8. **Bon automatisch abschneiden** nur einschalten, wenn der Drucker einen Abschneider hat.
9. **Speichern & Dienst neu starten**.
10. Einen Testbon drucken wie in Abschnitt 8.6.

### 8.3 Drucker mit Kabel am Laptop (seriell)

1. Den Drucker über seinen seriellen Anschluss und einen USB-Seriell-Adapter an den Server-Laptop anschließen. Den Treiber des Adapters installieren, falls Windows ihn nicht selbst findet.
2. Im Windows-**Geräte-Manager** unter **Anschlüsse (COM & LPT)** nachsehen, welchen COM-Port der Adapter bekommen hat, zum Beispiel `COM3`.
3. Im Verwaltungstool unter **Konfiguration → Bondrucker**: **Anschlussart** `serial`, **COM-Port** `COM3`.
4. **Baudrate** wie am Drucker eingestellt. Sie steht auf dem Selbsttest, beim Epson TM-T88II sind es ab Werk `9600`.
5. **Zeichen pro Zeile** und **Bon automatisch abschneiden** wie in 8.2.
6. **Speichern & Dienst neu starten** und einen Testbon drucken.

Den Adapter immer in dieselbe USB-Buchse stecken. In einer anderen Buchse kann Windows ihm eine andere COM-Nummer geben. Drucker mit USB-Anschluss funktionieren nur, wenn sie unter Windows als COM-Port erscheinen.

### 8.4 Was auf dem Bon steht

Im Verwaltungstool auf der Seite **Konfiguration**, Bereich **Bon-Inhalt**:

| Schalter oder Feld | Wirkung |
| --- | --- |
| Veranstaltungsname anzeigen | Name des laufenden Festes oben, fett und mittig |
| Datum + Uhrzeit anzeigen | Datum und Uhrzeit des Verkaufs, mittig |
| Preis anzeigen | Preis des Artikels |
| Fußzeilentext | Eine Zeile unter dem Artikel, zum Beispiel „Vielen Dank!“ oder „Nur am 04.10. gültig“. Leer = keine Zeile. |
| Kassierer anzeigen | Name der Person, die gedruckt hat. Es wird der Anzeigename aus dem Benutzerkonto gedruckt, ohne Anzeigenamen der Benutzername. |
| Kassierer-Bezeichnung | Wort vor dem Namen, zum Beispiel „Kassierer“ oder „Bedienung“ |

Danach **Speichern & Dienst neu starten**.

### 8.5 Wie der Bon aussieht

Im Verwaltungstool auf der Seite **Bon-Layout**:

| Schalter oder Feld | Wirkung |
| --- | --- |
| Trennlinie vor dem Kopfbereich | Linie ganz oben, vor dem Veranstaltungsnamen |
| Trennlinie nach Datum/Uhrzeit | Linie zwischen Kopf und Artikel |
| Trennzeichen | Zeichen, aus dem die Linie besteht: `-`, `=`, `*` oder `─` |
| Artikelname fett | Artikelname in fetter Schrift |
| Artikelname in GROSSBUCHSTABEN | Artikelname komplett groß |
| Preis in derselben Zeile wie der Artikel | Preis rechts neben dem Namen. Aus = Preis in einer eigenen, rechtsbündigen Zeile. |
| Leerzeilen vor dem Abschneiden | Papiervorschub am Ende. Bei Druckern, die zu früh abschneiden, auf 2 bis 4 erhöhen. |

Danach **Speichern** und auf dem **Dashboard** **Neu starten**. So sieht ein Bon mit den Standardwerten auf 80-mm-Papier aus:

```
              Weinfest 2026
          04.10.2026  19:42 Uhr
------------------------------------------
Bier 0,5 l                        4,00 EUR
Vielen Dank!
Kassierer: Anna (Bar)
```

Der Preis steht als „EUR“, weil viele Bondrucker das Euro-Zeichen nicht drucken können.

### 8.6 Bons an der Kasse drucken

Dafür braucht das Konto das Recht **Bon drucken** (Abschnitt 6.2) und in der Warengruppe das Recht **Buchen**.

1. Kategorie wählen und die Artikel antippen. **Keinen Chip scannen.**
2. Solange kein Chip gescannt ist, heißt der Knopf unten **Drucken** statt Buchen.
3. Den Betrag unter **Gesamt** bar kassieren.
4. **Drucken** tippen. Die Meldung „3 Bons gedruckt“ erscheint.
5. Die Bons dem Gast geben. Am Stand gibt der Gast einen Bon pro Artikel ab.

![Warenkorb ohne Chip mit 2× Bier und 1× Cola, Knopf „Drucken“](../images/bedieneranleitung/app/tablet/32_bondruck_warenkorb.png)

![Grüne Meldung „3 Bons gedruckt“](../images/bedieneranleitung/app/tablet/33_bons_gedruckt.png)

Gedruckt wird ein Bon pro Stück: zwei Bier und eine Cola ergeben drei Bons. Der Verkauf wird auf den gedachten Chip „BAR“ gebucht und erscheint in der Statistik wie jeder andere Verkauf. Wurde versehentlich ein Chip gescannt, steht dort wieder **Buchen**. Dann das Chip-Feld mit dem × leeren.

### 8.7 Wenn nichts gedruckt wird

- Bons gehen nie verloren. Ist der Drucker kurz nicht erreichbar, warten sie und werden gedruckt, sobald er wieder da ist. Die Meldung „Bons gedruckt“ erscheint trotzdem sofort. **Nicht noch einmal auf Drucken tippen**, sonst kommen die Bons doppelt.
- Prüfen: Strom, Papier, Deckel geschlossen, Kabel fest.
- Netzwerkdrucker: Stimmt die Drucker-IP-Adresse im Verwaltungstool mit dem Selbsttest überein?
- Kabeldrucker: Stimmt der COM-Port mit dem Geräte-Manager überein?
- Nach jeder Änderung **Speichern & Dienst neu starten**.

Weitere Prüfungen stehen im Handbuch für Systemadministratoren, Abschnitt 9.

## 9. Verkaufen im Betrieb

Für das Standpersonal reicht die Kurzanleitung. Hier steht der ganze Ablauf, auch für die Bonkasse.

### 9.1 Ein Verkauf Schritt für Schritt

1. In der Seitenleiste die Kategorie wählen. Auf dem Smartphone öffnet das Menü-Symbol oben links die Seitenleiste.
2. Die Artikel antippen. Jedes Antippen legt ein Stück mehr in den Warenkorb, dort steht dann zum Beispiel „2× 4,00 €“. Hat ein Artikel Optionen, erscheint zuerst die Auswahl.
3. Den Chip an den Leser halten, bei eingebautem NFC an die Rückseite des Tablets. Das Guthaben erscheint groß über dem Warenkorb. Die Reihenfolge ist egal, der Chip darf auch zuerst gescannt werden.
4. Unten prüfen: **Gesamt** ist der Preis, **Rest Guthaben** das, was danach auf dem Chip bleibt.
5. **Buchen** tippen. Die grüne Meldung „Buchung bestätigt“ erscheint, Warenkorb und Chip werden geleert.

![Gefüllter Warenkorb mit gescanntem Chip, Gesamt und Rest Guthaben](../images/bedieneranleitung/app/tablet/03_warenkorb_mit_chip.png)

![Grüne Meldung „Buchung bestätigt“](../images/bedieneranleitung/app/tablet/05_buchung_bestaetigt.png)

Einen Artikel entfernen Sie mit dem × daneben, **Leeren** löscht den ganzen Warenkorb. Das × im Chip-Feld entfernt den gescannten Chip.

### 9.2 Wenn das Guthaben nicht reicht

Ist **Rest Guthaben** rot, reicht das Guthaben nicht und **Buchen** ist grau. Dann Artikel entfernen oder den Gast zum Aufladen an die Bonkasse schicken. Grau ist Buchen außerdem, solange kein Chip gescannt oder der Warenkorb leer ist.

![Rest Guthaben in Rot, Buchen ist ausgegraut](../images/bedieneranleitung/app/tablet/09_guthaben_reicht_nicht.png)

### 9.3 Neuer Chip und Chip-Pfand

Wird ein Chip zum ersten Mal benutzt, steht über dem Guthaben **Neuer Kunde**. Ist ein Chip-Pfand eingestellt (Abschnitt 3.3), liegt im Warenkorb automatisch die gesperrte Zeile **Chip Pfand**. Sie lässt sich nicht entfernen. Der Pfand wird mit der ersten Buchung vom Guthaben abgezogen, meist mit der ersten Aufladung.

Beispiel bei 3 € Pfand: Der Gast zahlt 20 € bar, Sie buchen „Aufladen 20 €“, danach stehen 17 € auf dem Chip.

![Neuer Chip: Aufladen 20 € mit der gesperrten Zeile Chip Pfand, Rest Guthaben 17 €](../images/bedieneranleitung/app/tablet/04_aufladen_neuer_chip_pfand.png)

### 9.4 Guthaben aufladen (Bonkasse)

Dafür braucht das Konto das Recht **Aufladen** und **Buchen** in der Kategorie der Bonkasse (Abschnitt 6.2). Fehlt eines davon, lehnt die Kasse die Buchung ab.

1. Die Kategorie der Bonkasse wählen.
2. Aufladeartikel antippen, zum Beispiel zweimal „Aufladen 10 €“ für 20 €. Der Betrag steht im Warenkorb grün mit Minus davor, das ist eine Gutschrift für den Gast.
3. Den Chip scannen.
4. Bargeld in Höhe der Aufladeartikel annehmen, im Beispiel 20 €.
5. **Buchen** tippen. Das neue Guthaben erscheint.

### 9.5 Letzte Buchung stornieren

Nach jeder Buchung erscheint unter dem großen Knopf **Letzte Buchung stornieren**.

1. Antippen. Das Fenster „Buchung stornieren?“ zeigt die Artikel dieser Buchung.
2. Prüfen, ob es die richtige ist, und **Buchung stornieren** tippen.
3. Der Betrag geht zurück auf den Chip, ein verbrauchter Bestand wird zurückgebucht.

![Fenster „Buchung stornieren?“ mit den Artikeln der letzten Buchung](../images/bedieneranleitung/app/tablet/06_storno_dialog.png)

Stornieren lässt sich nur die letzte Buchung dieses Geräts. Nach der nächsten Buchung geht das nicht mehr. Wer nur „Storno 5 min“ hat, kann außerdem nur in den ersten fünf Minuten stornieren. Danach meldet die Kasse „Storno-Zeitfenster von 5 Minuten abgelaufen“, dann die Schichtleitung holen. Eine Auszahlung lässt sich nie stornieren, das Geld ist ja schon beim Gast.

### 9.6 Guthaben auszahlen (Bonkasse)

Dafür braucht das Konto das Recht **Auszahlen** (Abschnitt 6.2).

1. Die Kategorie der Bonkasse wählen und den Chip scannen.
2. Den Auszahlungs-Artikel antippen, zum Beispiel „Auszahlung“. Er muss allein im Warenkorb liegen.
3. Der Warenkorb zeigt die Zeile **Chip Pfand Rückgabe** und darunter den **Auszahlungsbetrag**: Restguthaben plus Pfand.
4. **Auszahlen** tippen.
5. Erst nach der Bestätigung genau den Auszahlungsbetrag bar auszahlen und den Chip einbehalten.

![Auszahlung: Chip Pfand Rückgabe +3,00 €, Auszahlungsbetrag 23,50 €, Knopf Auszahlen](../images/bedieneranleitung/app/tablet/07_auszahlung.png)

Der Chip ist danach wieder frei. Beim nächsten Gast gilt er als neuer Chip, und der Pfand wird wieder fällig.

### 9.7 Ohne Chip mit Bon verkaufen

Steht ein Bondrucker bereit, können Gäste auch bar zahlen und bekommen Papierbons. Wie das geht, steht in Abschnitt 8.6.

### 9.8 Hilfe anfordern

1. Oben rechts auf den roten Knopf **HILFE** tippen.
2. Im Fenster **Hilfe anfordern** auf **HILFE ANFORDERN** tippen. Der Knopf zeigt jetzt „HILFE Angefordert“.
3. Alle angemeldeten Notfall-Kontakte (Abschnitt 6.2) bekommen die Meldung „Hilfe benötigt!“ und antworten mit **Auf dem Weg**, **5 Minuten** oder **Nicht möglich**.
4. Die Antwort erscheint sofort an der Kasse, der Knopf zeigt dann zum Beispiel „Hilfe Kommt!“. Antippen zeigt, wer geantwortet hat.
5. Ist das Problem gelöst, den Knopf antippen und **Erledigt** wählen.

![Fenster „Hilfe anfordern“ mit dem Knopf HILFE ANFORDERN](../images/bedieneranleitung/app/tablet/12_hilfe_anfordern.png)

Damit Hilfe-Anfragen ankommen, muss mindestens ein Notfall-Kontakt während der Veranstaltung an einem Gerät angemeldet sein, zum Beispiel am Smartphone der Schichtleitung.

### 9.9 Schichtende

1. Unten in der Seitenleiste auf den eigenen Namen tippen und **Abmelden** wählen.
2. Tablets und Leser laden.

In der nächsten Schicht meldet sich die nächste Person mit ihrem eigenen Konto an.

## 10. Statistik anzeigen

Die Statistik zeigt Umsatz, alle Buchungen und den Stand jedes Chips, live während der Veranstaltung. Sie öffnet sich über **Statistik** in der Seitenleiste. Dafür braucht das Konto das Recht **Umsatz einsehen**, für den Reiter Transaktionen zusätzlich **Transaktionen einsehen** (Abschnitt 6.2).

### 10.1 Zeitraum wählen

Die Statistik zeigt immer den Betrieb, der gerade läuft: das aktuelle Fest oder den internen Betrieb (Abschnitt 11). Die Buchungen sind in **Perioden** eingeteilt, meist eine pro Veranstaltungstag. Eine neue Periode beginnt mit jedem Fest und mit jedem Tagesabschluss.

1. Oben auf das Feld mit dem Kalender tippen. Es zeigt die aktuelle Periode, zum Beispiel „Start (aktiv seit 03.10. 18:34)“.
2. Im Fenster **Zeitraum auswählen** eine oder mehrere Perioden ankreuzen, oder **Alle Zeiten** für alles seit Beginn.
3. **Übernehmen** tippen. Alle drei Reiter zeigen jetzt diesen Zeitraum.

### 10.2 Übersicht

![Statistik, Reiter Übersicht: Gesamtumsatz, Anzahl Transaktionen und Umsatz nach Kategorie](../images/bedieneranleitung/app/tablet/17_statistik_uebersicht.png)

- **Gesamtumsatz**: alle Verkäufe im Zeitraum, ohne Stornos. Aufladungen, Auszahlungen und Artikel mit „Von Statistik ausschließen“ zählen nicht mit. Barverkäufe mit Bon zählen mit.
- **Transaktionen**: Anzahl der Buchungen.
- **Nach Kategorie**: Umsatz je Kategorie, in Klammern die Anzahl. Eine Kategorie antippen, um den Umsatz jedes einzelnen Artikels zu sehen.

### 10.3 Transaktionen

![Statistik, Reiter Transaktionen: Suchfelder und Liste der Buchungen mit Chip, Uhrzeit und Benutzer](../images/bedieneranleitung/app/tablet/18_statistik_transaktionen.png)

- Jede Zeile ist eine Buchung mit Artikel, Chip-Nummer, Uhrzeit und dem Benutzer, der gebucht hat. Buchungen mit mehreren Artikeln lassen sich aufklappen.
- Stornierte Buchungen haben ein durchgestrichenes Symbol und zählen nicht zum Betrag.
- Aufladungen stehen mit Minus in der Liste, weil sie dem Gast gutgeschrieben werden.
- **Chip-UID suchen**: Den Chip an den Leser halten oder die Nummer tippen. Dann erscheinen nur die Buchungen dieses Chips. Praktisch, wenn ein Gast eine Buchung anzweifelt.
- **Kunden-Name suchen**: findet Chips, denen ein Name zugeordnet ist.

### 10.4 Chips

![Statistik, Reiter Chips: aktive Chips, Guthaben gesamt, Pfand ausstehend, Aufgeladen und Liste der Chips](../images/bedieneranleitung/app/tablet/19_statistik_chips.png)

| Kachel | Bedeutung |
| --- | --- |
| Aktive Chips | Chips, die gerade ausgegeben sind, von allen bisher benutzten |
| Guthaben gesamt | Summe aller Guthaben, die noch auf Chips stehen. So viel Bargeld muss für Auszahlungen bereitliegen. |
| Pfand ausstehend | Pfand für alle ausgegebenen Chips, der bei Rückgabe erstattet wird |
| Aufgeladen | Summe aller Aufladungen im Zeitraum |

Darunter steht jeder Chip mit Nummer, letzter Buchung, Guthaben und Status: **Aktiv** (beim Gast) oder **Frei** (ausgezahlt). Mit **Chip-UID suchen** finden Sie einen bestimmten Chip.

Für den Kassensturz an der Bonkasse zeigt **Aufgeladen**, wie viel Bargeld im Zeitraum für Aufladungen eingenommen wurde. Die Abrechnung als CSV-Datei für die Buchhaltung erstellen Sie im Verwaltungstool (Abschnitt 11.4).

## 11. Feste, Tagesabschluss und Datensicherung

Die Kasse läuft immer in einem von zwei Zuständen:

- **Fest läuft**: Buchungen, Statistik, Pager und Leaderboard gehören zu diesem Fest. Sein Name steht auf den Bons.
- **Interner Betrieb**: Es läuft kein Fest. Die Kasse funktioniert trotzdem, die Buchungen laufen auf „Intern“ mit eigener Statistik. Im internen Betrieb gibt es keinen Tagesabschluss und keine Leaderboard-Punkte.

Guthaben und Chips gehören keinem Fest. Sie bleiben beim Starten und Beenden eines Festes vollständig erhalten. Wer am Ende noch Guthaben hat, kann es beim nächsten Fest ausgeben oder es sich an der Bonkasse auszahlen lassen.

Bei der Installation legt NFC-Kasse automatisch ein erstes Fest „Hauptveranstaltung“ ohne Pfand an. Name und Pfand ändern Sie im Verwaltungstool unter **Konfiguration** (Abschnitt 3.3).

Kategorien, Artikel, Konten und Rechte gehören keinem Fest, ein Fest blendet nur Kategorien und Artikel ein (Abschnitt 5.6).

|  | Tagesabschluss | Fest beenden | Fest starten |
| --- | --- | --- | --- |
| Wo | Kasse, **Statistik** | Verwaltungstool, Seite **Feste** | Verwaltungstool, Seite **Feste** |
| Wann | am Ende jedes Veranstaltungstags | wenn die Veranstaltung vorbei ist | vor der nächsten Veranstaltung |
| Was passiert | Die aktuelle Periode endet, eine neue beginnt | Das Fest wird archiviert, offene Pager werden geschlossen, die Kasse wechselt in den internen Betrieb | Ein neues Fest mit Name, Pfand und den gewählten Kategorien beginnt, die Statistik zählt ab null |
| Guthaben der Gäste | bleiben | bleiben | bleiben |

Die Kassen merken jeden Wechsel nach wenigen Sekunden von selbst. Niemand muss sich neu anmelden.

### 11.1 Tagesabschluss machen

Dafür braucht das Konto das Recht **Umsatz einsehen**. Der Knopf erscheint nur, während ein Fest läuft.

1. In der Seitenleiste **Statistik** öffnen.
2. Oben rechts auf **Tagesabschluss** tippen.
3. Bei **Bezeichnung der neuen Periode** steht schon Datum und Uhrzeit. Sie können einen eigenen Namen eintragen, zum Beispiel „Samstag“.
4. **Abschließen** tippen.

![Dialog „Tagesabschluss“ mit dem Feld „Bezeichnung der neuen Periode“](../images/bedieneranleitung/app/tablet/20_tagesabschluss_dialog.png)

Danach zählt die Statistik ab null für die neue Periode. Den abgeschlossenen Tag sehen Sie jederzeit wieder, indem Sie ihn oben im Zeitraum auswählen (Abschnitt 10.1). Der Tagesabschluss unterbricht den Verkauf nicht.

### 11.2 Fest starten

1. Im Verwaltungstool die Seite **Feste** öffnen. Oben muss **Interner Betrieb** stehen. Läuft noch ein Fest, beenden Sie es zuerst (Abschnitt 11.3).
2. **Fest starten …** klicken.
3. **Festname** eingeben. Er steht auf jedem Bon. Pflichtfeld.
4. **Pfand pro Chip (€)** eingeben, `0` für kein Pfand. Pflichtfeld. Er gilt für Chips, die ab jetzt neu ausgegeben werden. Chips, die schon beim Gast sind, behalten ihren Pfand. **Datum** ist optional.
5. Unter **Artikel & Warengruppen** wählen, woran sich das Fest orientiert:
   - **Artikel aus „Intern“** oder **Artikel aus** einem früheren Fest: Das neue Fest zeigt dieselben Kategorien und Artikel wie dieses.
   - **Ohne Vorlage — Warengruppen unten wählen**: nur die Kategorien, die Sie darunter ankreuzen.
   - **Aus Vorlagen-Datei …**: eine Festvorlage (Abschnitt 11.5). Danach ankreuzen, was übernommen wird: Artikel & Warengruppen, Bon-Layout, Drucker-Einstellungen, Fußzeile & Kassierer-Text.
6. Unter **Warengruppen in diesem Fest** die Auswahl prüfen. Angekreuzt sind die Kategorien der gewählten Quelle. Eine zusätzlich angekreuzte Kategorie kommt mit allen ihren Artikeln. Einzelne Artikel blenden Sie später in der Artikelverwaltung ein und aus (Abschnitt 5.6).
7. **Bestände zurücksetzen** nur einschalten, wenn alle Artikel des Festes ohne Bestandszählung (unbegrenzt) starten sollen. Sonst zählt der Bestand weiter, denn er gehört dem Artikel.
8. **Fest starten** klicken. Das Verwaltungstool legt vorher automatisch eine Sicherung an.
9. Wurden Bon-Layout, Drucker oder Texte aus einer Vorlage übernommen, fragt das Tool, ob der Dienst jetzt neu starten soll. Erst danach gelten diese Einstellungen. Die Kassen sind dabei einige Sekunden nicht verbunden.

Konten und Rechte müssen Sie nicht neu vergeben, sie gelten in jedem Fest.

Tipp: Testen Sie vor der Veranstaltung im internen Betrieb und starten Sie das Fest erst danach. Dann stehen die Testbuchungen nicht in den Zahlen des Festes. Das Guthaben der Testchips bleibt aber erhalten, zahlen Sie die Testchips deshalb vorher aus.

### 11.3 Fest beenden

1. Im Verwaltungstool die Seite **Feste** öffnen und **Fest beenden …** klicken.
2. Das Fenster zeigt, wann zuletzt gebucht wurde, ob noch Bons ungedruckt oder Pager offen sind und wie viele Chips noch Restguthaben haben. Wird an den Kassen noch gebucht, warten Sie damit. Eine Buchung, die genau beim Wechsel ankommt, lehnt die Kasse ab, sie muss am Tablet wiederholt werden.
3. **Fest beenden** klicken. Das Verwaltungstool legt vorher automatisch eine Sicherung an.

Die Kasse läuft danach im internen Betrieb. Das beendete Fest steht unten in der Liste der Seite **Feste**. Dort können Sie es jederzeit als Abrechnung oder Vorlage speichern.

### 11.4 Abrechnung als CSV

1. Im Verwaltungstool auf der Seite **Feste** beim gewünschten Fest auf **Abrechnung als CSV (Buchungen, Artikel, Gesamtstatistik)** klicken.
2. Den Zeitraum wählen: **Gesamter Zeitraum** oder einzelne Perioden. **Weiter**.
3. Speicherort wählen.

### 11.5 Festvorlagen

Eine Festvorlage ist eine Datei mit allem, was ein Fest vorbereitet: die eingeschalteten Kategorien, Artikel mit Preisen, Optionen und Farben, Pfand, Bon-Layout, Drucker-Einstellungen und Bon-Texte. Guthaben, Chips, Buchungen, Benutzer und Lizenzen sind nie enthalten.

1. Im Verwaltungstool auf der Seite **Feste** beim gewünschten Fest **Als Festvorlage speichern** klicken.
2. Speicherort wählen. Die Datei heißt `Festvorlage_` plus Festname, mit der Endung `.json`.

Verwenden können Sie die Vorlage beim nächsten Fest (Abschnitt 11.2, **Aus Vorlagen-Datei …**), auch bei einem anderen Veranstalter oder auf einem anderen Server-Laptop. Kategorien und Artikel ordnet die Kasse dabei nach dem Namen zu: Vorhandene werden eingeblendet und bleiben, wie sie sind, fehlende werden aus der Vorlage angelegt.

### 11.6 Datensicherung

Auf der Seite **Daten** im Verwaltungstool sichern Sie die ganze Datenbank: alle Feste, Artikel, Benutzer, Buchungen und das Guthaben aller Chips.

- **Jetzt sichern** legt sofort eine Sicherung an, auf Wunsch mit Bezeichnung. Das geht auch im laufenden Betrieb.
- **Wiederherstellen** bei einer Sicherung in der Liste setzt die Datenbank auf diesen Stand zurück. Zur Bestätigung tippen Sie ein Wort ein. Der Dienst wird dafür kurz angehalten.
- **Sicherung importieren** spielt eine Sicherungsdatei von einem USB-Stick oder einem anderen Laptop ein.

Vor jedem Wiederherstellen und Importieren sichert das Tool automatisch den aktuellen Stand. Welche Sicherungen es automatisch anlegt und wo sie liegen, steht im Handbuch für Systemadministratoren, Abschnitt 10.

## 12. Ansicht, Kundenanzeige und Kiosk

### 12.1 Ansicht anpassen

Unter **Einstellungen → Design** passen Sie die Kasse an das Gerät an. Die Einstellungen gelten nur für dieses Gerät.

- **Voreinstellungen**: **Klein**, **Standard** oder **Groß** setzt alles auf einmal.
- **Allgemein → Schriftgröße**: Schrift der ganzen Kasse.
- **Produktbereich → Spalten**: wie viele Kacheln nebeneinander stehen. **Button-Textzeilen**: wie viele Zeilen ein langer Artikelname auf der Kachel bekommt.
- **Warenkorb → Schriftgröße**: Schrift im Warenkorb.

![Einstellungen, Reiter Design mit Voreinstellungen, Schriftgröße, Spalten und Button-Textzeilen](../images/bedieneranleitung/app/tablet/23_einstellungen_design.png)

Außerdem lässt sich in der Kasse der Trennbalken zwischen Kacheln und Warenkorb mit dem Finger verschieben, und die Seitenleiste auf dem Tablet mit dem Symbol neben „NFC Kasse“ einklappen. Wie Sie die Reihenfolge der Kacheln ändern, steht in Abschnitt 5.5.

### 12.2 Eigenes Konto und Abmelden

Unten in der Seitenleiste steht der Name des angemeldeten Benutzers. Antippen öffnet die Kontoseite, dort ist **Abmelden**. Abmelden geht auch unter **Einstellungen → Über**.

![Kontoseite mit dem Knopf Abmelden](../images/bedieneranleitung/app/tablet/27_konto.png)

### 12.3 Kundenanzeige

Die Kundenanzeige zeigt dem Gast auf einem zweiten Bildschirm, was im Warenkorb liegt, sein Guthaben und was nach der Buchung übrig bleibt. Dafür eignet sich ein altes Tablet oder ein Monitor mit Browser, der zum Gast zeigt.

1. Am zweiten Bildschirm im Browser `http://nfc-kasse.lan:8000/display` öffnen.
2. Unter **Standsauswahl** erscheinen alle Kassen, an denen gerade jemand angemeldet ist, mit dem Namen des Kontos. Die richtige Kasse antippen.
3. Ab jetzt zeigt der Bildschirm live den Warenkorb dieser Kasse mit **Gesamt**, **Aktuelles Guthaben** und **Nach Buchung**.

![Kundenanzeige, Standsauswahl mit einer aktiven Kasse](../images/bedieneranleitung/app/tablet/29_kundenanzeige_auswahl.png)

![Kundenanzeige einer Kasse mit Gesamt, aktuellem Guthaben und Guthaben nach der Buchung](../images/bedieneranleitung/app/tablet/30_kundenanzeige.png)

### 12.4 Kiosk für Gäste

An einem Kiosk-Gerät prüfen Gäste selbst ihr Guthaben, zum Beispiel neben der Bonkasse. Das Gerät kann nichts buchen.

1. Ein Konto anlegen, das nur die globale Berechtigung **Kiosk-Modus** hat (Abschnitt 6.2), zum Beispiel „kiosk“.
2. Am Kiosk-Gerät mit diesem Konto anmelden und, falls nötig, einen Bluetooth-Leser koppeln (Abschnitt 7).
3. Die Kasse zeigt jetzt nur noch das Kiosk-Bild und wartet auf einen Chip.
4. Hält ein Gast seinen Chip an den Leser, sieht er sein **Aktuelles Guthaben** und seine Buchungen. Mit **Fertig** oder nach kurzer Zeit kehrt das Gerät von selbst zum Startbild zurück.

![Kiosk wartet auf einen Chip](../images/bedieneranleitung/app/tablet/28_kiosk_start.png)

![Kiosk zeigt das aktuelle Guthaben und die Buchungen des Chips](../images/bedieneranleitung/app/tablet/28b_kiosk_guthaben.png)

Abmelden: Oben links fünfmal schnell hintereinander auf das Laden-Symbol neben „Kiosk“ tippen. So können Gäste das Gerät nicht versehentlich verlassen.

## 13. Checkliste und Fehlerhilfe

### 13.1 Checkliste vor der Veranstaltung

- Router eingerichtet, der Server-Laptop hat die Adresse 192.168.1.2, `http://nfc-kasse.lan:8000` öffnet die Kasse (Handbuch für Systemadministratoren)
- Energiesparen und Ruhezustand am Server-Laptop ausgeschaltet (Handbuch für Systemadministratoren, Abschnitt 4)
- NFC-Kasse installiert, im Verwaltungstool steht „Läuft“
- Admin-Passwort geändert
- Richtiger Veranstalter in Betrieb (Verwaltungstool, Seite Veranstalter, nur bei mehreren)
- Kategorien, Artikel und Preise angelegt, in der Bonkasse Aufladeartikel und ein Auszahlungs-Artikel
- Konten für alle Mitarbeiter mit ihren Kategorien, mindestens ein Notfall-Kontakt, an der Bonkasse die Rechte Aufladen und Auszahlen
- Jedes Tablet: App installiert, angemeldet, die richtigen Kategorien erscheinen
- NFC-Leser geladen und gekoppelt, Lesernummer auf dem Tablet notiert
- Bondrucker: Testbon gedruckt (falls genutzt)
- Testlauf: aufladen, verkaufen, stornieren, auszahlen
- Testchips ausgezahlt, danach im Verwaltungstool das Fest mit Name, Pfand und den richtigen Kategorien gestartet (Abschnitt 11.2)
- Server-Laptop einmal neu gestartet, der Dienst läuft danach von selbst
- Ladegeräte für Tablets und Leser, Wechselgeld und Bargeld für Auszahlungen bereit

### 13.2 Schnelle Hilfe

| Problem | Lösung |
| --- | --- |
| Das Symbol oben rechts zeigt keine Verbindung zum Server | Ist das Gerät im WLAN der Kasse? Stimmt die Server-URL samt `:8000`? Im Verwaltungstool prüfen, ob der Dienst läuft, sonst **Starten**. |
| Mit `nfc-kasse.lan` klappt die Anmeldung nicht | Auf der Anmeldeseite `http://192.168.1.2:8000` wählen. Den Router prüft das Handbuch für Systemadministratoren. |
| Der Dienst startet nicht, das Dashboard steht auf „Gestoppt“ | Im Verwaltungstool die Seite **Lizenzen** prüfen: Steht bei der Hauptlizenz nicht **Gültig**, startet der Dienst nicht (Abschnitt 3.5). |
| Nach dem Speichern im Verwaltungstool steht der Dienst auf „Gestoppt“ | Den zuletzt geänderten Wert prüfen, oft ein Komma statt Punkt im Chip-Pfand. Korrigieren und **Speichern & Dienst neu starten**. |
| Eine Änderung im Verwaltungstool wirkt nicht | **Speichern & Dienst neu starten** benutzen, beim Bon-Layout danach **Neu starten**. |
| „Nach Geräten suchen“ findet den Leser nicht | Leser eingeschaltet und geladen? Bluetooth am Gerät an? Im Browser: Chrome oder Edge, Adresse als vertrauenswürdig eingetragen (Abschnitt 7.3)? |
| Leser zeigt „Verbunden“, aber nichts passiert | Leser aus- und wieder einschalten, die App verbindet sich von selbst neu. Im Browser kann es bis zu 90 Sekunden dauern. |
| USB-Leser tippt, aber nichts passiert | Zuerst ins Chip-Feld tippen. |
| Android erkennt den Chip nicht | NFC in den Android-Einstellungen einschalten, Schutzhülle abnehmen, Chip 1 bis 2 Sekunden ruhig halten. |
| Buchen ist grau | Chip scannen. Ist Rest Guthaben rot, reicht das Guthaben nicht (Abschnitt 9.2). |
| „Doppelbuchung verhindert — bitte 2 Sekunden warten“ | Dieselbe Buchung wurde zweimal getippt. Kurz warten und am Guthaben prüfen, ob die erste durchgegangen ist. |
| „Storno-Zeitfenster von 5 Minuten abgelaufen“ | Die Schichtleitung holen (Abschnitt 9.5). |
| „Keine Buchungsberechtigung für eine oder mehrere Warengruppen“ oder leere Seitenleiste | Dem Konto unter **Benutzer** die Kategorie mit **Buchen** geben (Abschnitt 6.3). Ist die Kategorie im laufenden Fest ausgeblendet, in der Artikelverwaltung einschalten (Abschnitt 5.6). |
| „Berechtigung 'Aufladen' erforderlich“ oder „Berechtigung 'Auszahlen' erforderlich“ | Dem Konto unter **Benutzer** die globale Berechtigung **Aufladen** bzw. **Auszahlen** geben (Abschnitt 6.2). |
| Eine Buchung wird abgelehnt: „Das Fest wurde gerade gewechselt“ oder „Ein Artikel ist in diesem Fest nicht mehr aktiv“ | Die Kasse lädt das Fest neu. Die Buchung wiederholen. Fehlt der Artikel danach, ist er im Fest ausgeblendet (Abschnitt 5.6). |
| Alle Kassen sind abgemeldet, das Passwort passt nicht mehr | Im Verwaltungstool wurde der Veranstalter gewechselt (Abschnitt 3.6). Mit einem Konto des Veranstalters in Betrieb anmelden. |
| Bons werden nicht gedruckt | Abschnitt 8.7. |
| Alle Geräte wurden abgemeldet | Einfach neu anmelden. Passiert, wenn die Einstellungsdatei des Servers neu angelegt wurde. |

Detaillierte Fehlersuche steht im Handbuch für Systemadministratoren, Abschnitt 12. Kommen Sie nicht weiter, schreiben Sie an **kontakt@nfc-kasse.de** und hängen Sie die Protokolle aus `C:\ProgramData\NFC-Kasse\logs\` an (Verwaltungstool → Dashboard → **Protokolle öffnen**).
