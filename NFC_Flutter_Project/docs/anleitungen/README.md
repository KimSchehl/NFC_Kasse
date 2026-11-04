# Anleitungen zur NFC-Kasse

Stand: 4. November 2026 (Markdown, PDF und Word)

| Anleitung | Für wen | Dateien |
| --- | --- | --- |
| Bedieneranleitung | Veranstalter: Installation, Verwaltungstool, Artikel, Rechte, Bluetooth-Leser, Bondrucker, Statistik, Feste, Tagesabschluss, Datensicherung | [PDF](Bedieneranleitung.pdf) · [Word](Bedieneranleitung.docx) · [Markdown](Bedieneranleitung.md) |
| Handbuch für Systemadministratoren | Technik: Router, feste IP 192.168.1.2, nfc-kasse.lan, Dienst, config.env, Sicherungsdateien, Fehlersuche | [PDF](Handbuch_Systemadministratoren.pdf) · [Word](Handbuch_Systemadministratoren.docx) · [Markdown](Handbuch_Systemadministratoren.md) |
| Kurzanleitung Standpersonal | Leute am Stand: Chip scannen, Artikel antippen, buchen | [PDF](Kurzanleitung_Standpersonal.pdf) · [Word](Kurzanleitung_Standpersonal.docx) · [Markdown](Kurzanleitung_Standpersonal.md) |
| Zusatzfunktionen Pager und Leaderboard | Veranstalter mit Lizenz für Pager oder Leaderboard | [PDF](Zusatzfunktionen_Pager_Leaderboard.pdf) · [Word](Zusatzfunktionen_Pager_Leaderboard.docx) · [Markdown](Zusatzfunktionen_Pager_Leaderboard.md) |

## Formate

- **PDF** zum Drucken und Weitergeben (A4).
- **Word** zum Weiterbearbeiten.
- **Markdown** für GitHub. Die Bilder werden aus `../images/bedieneranleitung/` geladen.

Alle Bilder liegen in [`../images/bedieneranleitung/`](../images/bedieneranleitung/README.md). Die README dort listet jedes Bild und sagt, welche Fotos und Screenshots noch fehlen.

Jedes Thema steht in genau einer Anleitung, die anderen verweisen darauf. Die Bedienung steht in der Bedieneranleitung, die technischen Einzelheiten dazu im Handbuch, Lizenzen in den Zusatzfunktionen.

## Noch offen

- Die Screenshots der Kassen-App, der Kundenanzeige, von Pager und Leaderboard sind vom 4. November 2026, die des Verwaltungstools (Ordner `windows/`) und die Fotos vom NFC-Leser (Ordner `hardware/`) ebenfalls.
- Es fehlen noch: Fotos von Bondrucker, gedrucktem Bon und Aufbau sowie Screenshots der Router-Oberfläche (LuCI).

## PDF und Word neu erzeugen

PDF und Word entstehen mit pandoc aus den Markdown-Dateien (Skript `_export/build.py`, braucht pandoc, Python 3 mit Playwright und Chromium; Aufruf `python _export/build.py`).
