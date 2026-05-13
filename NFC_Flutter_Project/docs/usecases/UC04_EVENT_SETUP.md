# UC04 — Event Setup (First Install / New Event)

**Actor:** Administrator
**Situation:** New machine, or new event year

---

## One-Time Installation

```
1. Copy the backend/ folder to the thin client (Fujitsu S920)

2. Install dependencies
   pip install -r requirements.txt

3. Create the database
   python init_db.py
   → Creates kasse.db with all tables, permissions, and an admin user
   → Default credentials: admin / admin  ← CHANGE IMMEDIATELY

4. Start the server
   uvicorn main:app --host 0.0.0.0 --port 8000
   (or use a systemd service / auto-start script for production)

5. Verify: open http://localhost:8000/docs in a browser
   → All routers should be listed
   → Use the Authorize button (top right) to log in and test endpoints
```

---

## Per-Event Setup (via App or Swagger UI)

```
1. Log in with admin / admin
   → IMMEDIATELY navigate to Account → Abmelden, then change password via
     PUT /api/users/1  { "password": "newpassword" }

2. Create categories
   POST /api/products/categories  for each:
   e.g.  { "name": "Bonkasse", "sort_order": 1 }
         { "name": "Bar",      "sort_order": 2 }
         { "name": "Essen",    "sort_order": 3 }

3. Create products for each category
   POST /api/products/  for each:
   e.g.  { "name": "Bier 0,5L", "price": 3.50, "category_id": 2, "color": "#90CAF9" }
         { "name": "Pfand Rückgabe", "price": -2.00, "category_id": 2 }
   → Negative prices are valid (refunds, deposit returns)
   → Colors are optional hex strings (#RRGGBB)

4. Create staff accounts
   POST /api/users/  { "username": "vendor1", "password": "...", "display_name": "Anna" }

5. Assign permissions and categories per user
   Option A — Role template (recommended):
     GET  /api/users/role-templates           ← lists "Standverkäufer", "Veranstaltungs-Verantwortlicher"
     POST /api/users/{id}/apply-template/{template_id}
   Option B — Manual:
     PUT  /api/users/{id}/permissions  { "permission_ids": [...] }
     PUT  /api/users/{id}/categories   { "categories": [...] }

6. Run a test booking
   → Open the Flutter app on a tablet
   → Scan a test wristband → top up 10 € via POST /api/topup/
   → Buy one product → verify balance is deducted correctly
   → Cancel the booking → verify balance is restored

7. Network setup
   → Switch on the TP-Link access point (Wi-Fi "Kasse")
   → Set backend IP in nfc_kasse_app/lib/config/api_config.dart:
       static const baseUrl = 'http://192.168.1.1:8000';
   → Rebuild and deploy the Flutter app to all tablets
   → Verify each tablet connects and can load categories
```

---

## Pre-Event Checklist

- [ ] Admin password changed from default "admin"
- [ ] All categories created and sorted correctly
- [ ] All products created with correct names, prices, and colours
- [ ] Negative-price products (Pfand Rückgabe, Aufladen) created where needed
- [ ] All staff accounts created with correct permissions and category access
- [ ] Test booking completed successfully on at least one tablet
- [ ] Backup of `kasse.db` created before the event starts
- [ ] All tablets connected to Wi-Fi "Kasse"
- [ ] Flutter app opens on each tablet and reaches the backend (`/health` returns 200)
- [ ] At least one top-up and one cancellation tested end-to-end
