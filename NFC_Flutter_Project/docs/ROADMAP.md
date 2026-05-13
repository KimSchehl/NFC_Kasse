# NFC-Kasse — Roadmap & Zukunftsideen

Gesammelte Ideen für zukünftige Erweiterungen.
Aktuelle Phase: **Lokal / Single-Event / SQLite**

---

## Infrastruktur & Deployment

- [ ] **Cloud-Anbindung**: Migration von SQLite auf PostgreSQL für Cloud-Betrieb.
      Backend so abstrahieren (Repository-Pattern), dass der DB-Wechsel minimal invasiv ist.
- [ ] **Hybrid-Login in der App**: Vor dem Login auswählen ob "Cloud" oder "Self-Hosted" (eigene Server-URL eingeben).
- [ ] **Kassen-Netzwerk Integration**: Lokales Kassen-WLAN (TP-Link AP) soll optional in ein bestehendes
      Veranstaltungs-WLAN integriert werden können (VLAN, Bridging o.ä.).

---

## Multi-Tenant / Multi-Event (Cloud)

- [ ] **Mehrere gleichzeitige Veranstaltungen**: z.B. zwei Feste am gleichen Wochenende unter demselben Betreiber.
- [ ] **Weinfest-Modell (Hof-Hierarchie)**:
      - Jeder Hof = eigene Instanz mit eigenen Rollen, Mitarbeitern, Statistiken, Transaktionen.
      - Hof-Verantwortlicher verwaltet seinen Bereich vollständig selbst.
      - Übergeordneter Fest-Betreiber sieht Gesamtstatistik (Finanzen aller Höfe aggregiert).
      - Gleichzeitig können an anderen Orten weitere Feste laufen (echter Multi-Tenant).
      - DB-Struktur: `tenant → event → stand/hof → user` Hierarchie vorbereiten.

---

## NFC / Hardware

- [ ] **Daten auf Tag schreiben**: UID mit Besitzername beschreiben, weitere verschlüsselte Daten auf Tag speichern.
- [ ] **Sicherheit**: Guthaben darf NIEMALS auf dem Tag selbst liegen (manipulierbar).
      Guthaben bleibt immer server-seitig in der DB. Tag = nur Identifikator.
      Verschlüsselte Zusatzdaten (Name etc.) mit Server-Key signieren, sodass Manipulation erkennbar ist.
- [ ] **USB NFC Reader**: HID-Keyboard-Input als Fallback für Windows/Desktop bereits berücksichtigt.

---

## Gäste-Portal

- [ ] **Guthaben von zuhause aufladen**: Web-Portal für Endkunden.
- [ ] **Zahlungsanbieter**: Google Pay und PayPal als erste Integrationen.
- [ ] **OAuth Login**: Google/Apple Login für Gäste (nicht für Kassenpersonal).
- [ ] **NFC-Armband Verknüpfung**: Gast verknüpft sein Armband einmalig mit seinem Konto,
      lädt Guthaben auf → geht ohne Geldbeutel zum Fest.

---

## App / UX

- [ ] **Biometrie**: Fingerabdruck / Face ID als Schnell-Entsperrung nach erstem Login.
- [ ] **PIN-Modus**: 4-stelliger PIN für schnellen Kassenwechsel (mehrere Verkäufer, ein Tablet).
- [ ] **Admin: Buchungen sperren**: Stornieren/Verändern von Buchungen für Admin deaktivierbar machen
      (Compliance, Kassenprüfung).

---

## Vertrieb / Pakete

- [ ] **Zwei Produkt-Pakete**: 
      - *Lokal*: Self-hosted auf Mini-PC, einmaliger Kauf oder Miete.
      - *Cloud*: SaaS-Modell, monatliche Gebühr, automatische Updates.

