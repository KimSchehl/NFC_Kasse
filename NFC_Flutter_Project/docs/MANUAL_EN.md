# NFC-Kasse — User Manual

**Version 1.0 · English**

---

## Table of Contents

1. [What is NFC-Kasse?](#1-what-is-nfc-kasse)
2. [Getting Started — First Login](#2-getting-started--first-login)
3. [The Interface](#3-the-interface)
4. [Staff Guide — Using the Cash Register](#4-staff-guide--using-the-cash-register)
   - 4.1 [Scanning a Guest Wristband](#41-scanning-a-guest-wristband)
   - 4.2 [Adding Products to the Cart](#42-adding-products-to-the-cart)
   - 4.3 [Completing a Booking](#43-completing-a-booking)
   - 4.4 [Cancelling the Last Booking](#44-cancelling-the-last-booking)
   - 4.5 [New Customers](#45-new-customers)
   - 4.6 [Insufficient Balance](#46-insufficient-balance)
5. [Manager Guide](#5-manager-guide)
   - 5.1 [Statistics](#51-statistics)
   - 5.2 [Unlimited Cancellation](#52-unlimited-cancellation)
6. [Admin Guide — Setup & Configuration](#6-admin-guide--setup--configuration)
   - 6.1 [Initial Setup](#61-initial-setup)
   - 6.2 [Creating Categories](#62-creating-categories)
   - 6.3 [Creating Products](#63-creating-products)
   - 6.4 [Managing Staff Accounts](#64-managing-staff-accounts)
   - 6.5 [Edit Mode — Editing Products During the Event](#65-edit-mode--editing-products-during-the-event)
   - 6.6 [Topping Up Guest Balances](#66-topping-up-guest-balances)
   - 6.7 [Paying Out Guest Balances](#67-paying-out-guest-balances)
   - 6.8 [Pre-Event Checklist](#68-pre-event-checklist)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. What is NFC-Kasse?

NFC-Kasse is a cashless payment system for events. Guests load credit onto NFC wristbands at the entrance (Bonkasse). At each bar or food stand, staff scan the wristband and book products — the price is deducted from the wristband balance automatically.

No cash changes hands at the stands. The entire system runs on a local Wi-Fi network; no internet connection is required.

**Roles at a glance:**

| Role | What they do |
|---|---|
| Bonkasse staff | Top up guest wristbands with cash |
| Stand vendor | Scan wristbands and book products |
| Event manager | All of the above + cancel any booking + view statistics |
| Administrator | Full access: setup, user management, product management |

---

## 2. Getting Started — First Login

1. Open the NFC-Kasse app on your tablet or phone.
2. Enter your **username** and **password** (provided by your administrator).
3. Tap **Anmelden**.

The app stays logged in for 24 hours. If you are logged out automatically, repeat the steps above.

To log out manually:
- Tap your name at the bottom of the left sidebar → **Abmelden**
- Or: go to **Einstellungen** → **Abmelden**

---

## 3. The Interface

### On a Tablet (wide screen)

The left sidebar is always visible:

```
┌──────────────────────────────────────────┐
│ NFC Kasse logo   │  Main content area    │
│                  │                       │
│ KATEGORIEN       │  (POS / Stats / etc.) │
│  · Bar           │                       │
│  · Essen         │                       │
│                  │                       │
│ Statistik        │                       │
│ Einstellungen    │                       │
│ [Your name]      │                       │
└──────────────────────────────────────────┘
```

### On a Phone (narrow screen)

Tap the **☰ hamburger menu** (top left) to open the navigation drawer. The main content area fills the whole screen.

---

## 4. Staff Guide — Using the Cash Register

The **POS screen** is the main cash register view. It loads automatically after login.

### 4.1 Scanning a Guest Wristband

**With a USB HID reader (desktop / tablet with keyboard):**
1. Tap the text field at the top (it shows "UID eingeben oder USB-Lesegerät verwenden...").
2. Hold the wristband against the reader.
3. The reader types the UID and presses Enter automatically.
4. The customer's balance appears immediately.

**With native NFC (Android phone with NFC):**
1. The text field shows "NFC scannen oder UID eingeben..." with an NFC icon.
2. Hold the wristband to the back of the phone.
3. The app detects the tag and loads the balance automatically — no button press needed.

After a scan, the UID stays visible in the input field. The customer panel on the right shows the current balance.

### 4.2 Adding Products to the Cart

1. Select a category from the left sidebar (e.g. "Bar").
2. Tap a product tile in the grid — it is added to the cart.
3. Tap the same product again to add another unit (quantity increments automatically).
4. To remove an item from the cart, tap the **×** next to it.
5. To empty the entire cart, tap **Leeren** in the cart header.

The cart always shows:
- Each product with quantity and subtotal
- **Gesamt:** — total amount due
- **Rest Guthaben:** — customer balance after this purchase (shown in red if negative)

### 4.3 Completing a Booking

1. Confirm that the correct customer is scanned (check the balance shown).
2. Verify the cart contents.
3. Tap **✓ Buchen**.

The balance is deducted immediately. The cart clears and the new balance is displayed. A **Letzte Buchung stornieren** button appears — see section 4.4.

> The **Buchen** button is disabled if:
> - The cart is empty
> - No customer is scanned
> - The purchase would result in a negative balance

### 4.4 Cancelling the Last Booking

You have **5 minutes** to cancel the last booking.

1. Tap **↩ Letzte Buchung stornieren** (below the Buchen button).
2. A dialog shows the booked items, the total, and the booking time.
3. Tap **Stornieren** to confirm.

The full amount is refunded to the customer's balance. The storno button disappears after a successful cancel.

> If 5 minutes have passed, the button is still visible but the server will refuse the cancellation with an error message. Only managers with unlimited cancel rights can cancel older bookings.

### 4.5 New Customers

When a wristband is scanned for the first time, a red **"Neuer Kunde"** badge appears and the balance shows **0,00 €**.

This means the guest has not topped up yet. You can:
- Direct them to the Bonkasse to load credit, then scan again.
- If they pay cash at the stand: book the products anyway — the balance will go negative, which records the debt. The Bonkasse can settle it later.

### 4.6 Insufficient Balance

The **Buchen** button becomes grey and disabled when the cart total exceeds the customer's balance. The "Rest Guthaben" is shown in red.

Options:
- Remove some products from the cart.
- Ask the guest to top up at the Bonkasse.

---

## 5. Manager Guide

### 5.1 Statistics

Navigate to **Statistik** in the sidebar.

**Übersicht tab:**
- Total revenue (sum of all non-cancelled bookings)
- Total number of transactions
- Revenue broken down by category

**Transaktionen tab:**
- The 50 most recent transactions with product name, NFC UID, time, and price
- Refunds and deposit returns are shown in a different colour

### 5.2 Unlimited Cancellation

Managers with the `sales.booking.cancel_unlimited` permission can cancel any booking, regardless of when it was made. The process is the same as for vendors (section 4.4), but without the 5-minute time limit.

---

## 6. Admin Guide — Setup & Configuration

### 6.1 Initial Setup

1. Start the backend on the thin client:
   ```
   python init_db.py
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```
2. Open `http://localhost:8000/docs` in a browser to verify the server is running.
3. Log in with **admin / admin**.
4. **Change the admin password immediately:**
   - Use the Swagger UI: `PUT /api/users/1` with `{ "password": "your-new-password" }`

### 6.2 Creating Categories

Categories are the tabs in the POS sidebar (e.g. "Bar", "Essen", "Bonkasse").

**Via the Flutter app:**
1. Log in as admin (or a user with `categories.create`).
2. Tap **Neue Kategorie** at the bottom of the category list in the sidebar.
3. Enter the category name and tap **Erstellen**.
4. The new category is automatically selected.

**Via Swagger UI:**
```
POST /api/products/categories
{ "name": "Bar", "sort_order": 2 }
```

To rename or reorder: tap the **pencil icon** next to a category name (in Bearbeitungsmodus), or use `PUT /api/products/categories/{id}`.

### 6.3 Creating Products

**Via the Flutter app (recommended):**
1. Open the category you want to add products to.
2. Enable **Bearbeitungsmodus** (bottom of the sidebar).
3. Tap the **+** tile that appears in the product grid.
4. Fill in the name, price, and optional colour.
5. Tap **Speichern**.

**Via Swagger UI:**
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

**Tips:**
- **Negative prices** are valid and useful: use them for deposit returns (Pfand Rückgabe) or top-up products (Aufladen) that add credit back to the wristband.
- **Colours** help staff find products quickly. Use the colour picker in the app, or provide a hex colour code (`#RRGGBB`).
- **Deactivating a product** (toggle in Bearbeitungsmodus) removes it from the grid without deleting its sales history.

### 6.4 Managing Staff Accounts

**Creating a new user:**

Via the Flutter app (Benutzer screen, requires `users.create` permission) or:
```
POST /api/users/
{ "username": "vendor1", "password": "geheim123", "display_name": "Anna" }
```
Passwords must be at least 6 characters.

**Assigning permissions:**

The quickest way is to apply a role template:
```
POST /api/users/{id}/apply-template/{template_id}
```

Predefined templates:

| Template | Permissions included |
|---|---|
| Standverkäufer | Book, 5-min cancel, view balance, view categories, local settings |
| Veranstaltungs-Verantwortlicher | All of above + top-up, payout, unlimited cancel, create categories, view stats, manage users |

**Assigning category access:**

After applying a template, grant access to specific categories:
```
PUT /api/users/{id}/categories
{
  "categories": [
    { "category_id": 2, "can_edit": false, "can_delete": false, "can_deactivate": true }
  ]
}
```

A vendor who is assigned `categories.view` but has no category access rows will see an empty sidebar. Always assign at least one category.

**Deactivating a user:**

```
DELETE /api/users/{id}
```
Sets `active=0`. The user can no longer log in; their historical sales are preserved.

### 6.5 Edit Mode — Editing Products During the Event

Enable **Bearbeitungsmodus** from the bottom of the sidebar (visible when on the POS screen and you have edit rights).

In edit mode you can:
- **Add** a new product (tap the + tile)
- **Edit** an existing product (tap its tile)
  - Change name, price, colour, sort order
- **Deactivate / reactivate** a product (toggle in the edit dialog)
- **Delete** a product (trash icon, requires `can_delete`)
- **Edit** category name and sort order (pencil icon next to category name)

Changes take effect immediately for all connected devices.

### 6.6 Topping Up Guest Balances

Top-ups are performed at the Bonkasse (entrance) using the API directly or a dedicated Bonkasse interface. The Flutter app does not currently have a top-up screen.

```
POST /api/topup/
{
  "nfc_uid": "04ABCDEF",
  "amount": 20.00,
  "payment_method": "cash"
}
```
Response includes the new balance.

### 6.7 Paying Out Guest Balances

At the end of the event, guests can request a cash refund of their remaining balance:

```
POST /api/topup/payout/{nfc_uid}
```

This zeroes out the balance and records the payout in the audit trail.

### 6.8 Pre-Event Checklist

- [ ] Admin password changed
- [ ] All categories created and in the correct order
- [ ] All products created with correct prices and colours
- [ ] Negative-price products added where needed (Pfand Rückgabe, Aufladen)
- [ ] All staff accounts created and assigned appropriate permissions and categories
- [ ] Test booking completed and verified on at least one tablet
- [ ] Test cancellation verified
- [ ] Backup of `kasse.db` created before the event
- [ ] All tablets connected to Wi-Fi "Kasse"
- [ ] App opens and loads categories on every tablet

---

## 7. Troubleshooting

**The app shows "Connection refused" or a network error**

- Check that the backend server is running on the thin client.
- Verify the tablet is connected to the "Kasse" Wi-Fi network.
- Check the configured server URL in the Settings screen. It should be `http://192.168.1.1:8000` (or the actual IP of your thin client).

**NFC is not detected (mobile)**

- Ensure NFC is enabled in the phone's Android settings.
- Hold the wristband still against the middle/back of the phone for 1–2 seconds.
- Some phone cases block NFC — try removing the case.

**USB reader types the UID but nothing happens**

- Tap the UID input field first so it has focus.
- Ensure the reader sends a newline (`\n`) after the UID. Most HID readers do this by default.

**"Buchen" button is disabled even though the cart has items**

- Check whether a customer is loaded (balance is displayed). If not, scan a wristband first.
- Check the "Rest Guthaben" value — if it is red (negative), the button is intentionally disabled. Remove items or ask the guest to top up.

**"Storno" fails with "Cancel window expired"**

- The 5-minute window has passed. Contact a manager with unlimited cancel rights.

**A product shows as inactive (greyed out)**

- The product has been deactivated. Enable Bearbeitungsmodus and reactivate it via the edit dialog.

**The statistics screen shows no data**

- Ensure you have the `statistics.revenue` permission. Contact your administrator.
- If the event just started, there may genuinely be no transactions yet.
