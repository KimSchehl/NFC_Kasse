# Flutter Frontend — Screens

Flutter 3 · Dart · Riverpod · Android · iOS

---

## Navigation Architecture

The app uses a single `MainShell` widget that switches between screens using a `currentScreenProvider` (Riverpod `StateProvider`). Navigation is handled by `AppSidebar`.

**Tablet / wide layout (≥ 600 px wide):**
```
┌──────────────────────────────────────────┐
│  AppSidebar (220 px)  │  Screen content  │
│  ─ NFC Kasse logo     │                  │
│  ─ KATEGORIEN         │                  │
│    · Bar              │                  │
│    · Essen            │                  │
│  ─ Statistik          │                  │
│  ─ Benutzer           │                  │
│  ─ Einstellungen      │                  │
│  ─ [user account]     │                  │
└──────────────────────────────────────────┘
```

**Phone / narrow layout (< 600 px wide):**
```
┌────────────────────────────┐
│  ☰  Kasse          AppBar  │
├────────────────────────────┤
│  Screen content            │
└────────────────────────────┘
```
The hamburger menu opens a `Drawer` containing the full `AppSidebar`.

---

## AppSidebar (`app_sidebar.dart`)

Sections (top to bottom):
1. **Logo bar** — "NFC Kasse" with point-of-sale icon
2. **Category list** — only the categories visible to the current user; tapping a category opens the POS screen for that category
3. **Neue Kategorie** button — visible only to users with `categories.create`
4. **Statistik** — visible only with `statistics.*` permissions
5. **Benutzer** — visible only with `users.*` permissions
6. **Einstellungen** — always visible (server URL, version, logout)
7. **Bearbeitungsmodus** toggle — visible on POS screen to managers and users with edit access to the selected category; enables inline product editing
8. **Account tile** — shows the current user's display name; navigates to the Account screen

---

## Screens

### Login Screen (`login_screen.dart`)

Shown when no valid token is stored. Covers the full screen.

**Elements:** App logo, username field, password field (obscured), login button, error text on failure.

**Flow:**
1. User enters credentials and taps login
2. `POST /api/auth/login` → tokens stored in `flutter_secure_storage`
3. `GET /api/auth/me` → user profile loaded into `authProvider`
4. App transitions to `MainShell` (POS screen by default)

---

### POS Screen (`pos_screen.dart`)

The main cash register view. Contains two sub-layouts depending on available width.

#### Wide POS layout (content area ≥ 700 px)
```
┌────────────────────────────────┬──────────────┐
│  [USB icon]  UID eingeben... ▶ │ Neuer Kunde  │
│                                │  0,00 €      │
├────────────────────────────────┤              │
│                                ├──────────────┤
│   Product Grid                 │  Warenkorb   │
│                                │  ─────────── │
│  ┌──────────┐ ┌──────────┐     │  Bier  2,50€ │
│  │  Bier    │ │ Schorle  │     │  ─────────── │
│  │  2,50 €  │ │  3,50 €  │     │  Gesamt:     │
│  └──────────┘ └──────────┘     │  2,50 €      │
│                                │  Rest: 0,00 €│
│                                │ [✓ Buchen]   │
│                                │ [↩ Stornieren│
└────────────────────────────────┴──────────────┘
```
Cart panel is fixed at 300 px wide on the right.

#### Narrow POS layout (content area < 700 px)
```
┌────────────────────────────────┐
│  [USB icon]  UID eingeben...▶  │  Neuer Kunde │
│                                │  0,00 €      │
├────────────────────────────────┤
│   Product Grid (scrollable)    │
│                                │
│  ┌──────────┐ ┌──────────┐     │
│  │  Bier    │ │ Schorle  │     │
│  │  2,50 €  │ │  3,50 €  │     │
│  └──────────┘ └──────────┘     │
├────────────────────────────────┤  ← always visible
│  Warenkorb                     │
│  Bier                  2,50 €  │
│  ─────────────────────────     │
│  Gesamt:               2,50 €  │
│  Rest Guthaben:        0,00 €  │
│  [✓ Buchen              ]      │
│  [↩ Letzte Buchung stornieren] │
└────────────────────────────────┘
```
Cart is always visible in the bottom half — no pop-up or drawer needed.

#### NFC Input Field
- **USB HID reader**: Shows USB icon. Reader types UID as keyboard input; pressing Enter (or the `\n`/`\r` terminator the reader appends) triggers the lookup. The UID remains visible in the field after the scan.
- **Native NFC** (mobile): Shows NFC icon in primary colour. `nfc_manager` fires the callback when a tag is detected; the UID is submitted immediately without pressing Enter.

#### Customer Info Panel
Appears to the right of the NFC input field.
- No customer scanned → "Bitte NFC-Chip scannen"
- New UID (not in database) → red **"Neuer Kunde"** badge + balance **0,00 €**
- Known customer → balance displayed in primary colour (positive) or error colour (zero / negative)

#### Cart Panel
- Lists all added products with product name, quantity × price (if > 1), subtotal, and a remove (×) button
- **Gesamt:** row shows the total of all cart items
- **Rest Guthaben:** shows customer balance minus cart total; displayed in error colour when negative
- **Buchen** button: disabled when the cart is empty, no customer is loaded, or the rest balance would be negative
- **Letzte Buchung stornieren** button: only visible when a recent booking exists; opens the cancel dialog

#### Edit Mode
When Bearbeitungsmodus is active, product tiles show an edit overlay and category tiles show an edit icon. Users can create, rename, recolour, reorder, deactivate, and delete products inline.

---

### Statistics Screen (`stats_screen.dart`)

Two tabs:

**Übersicht tab:**
- "Gesamtumsatz" card — total revenue in €
- "Transaktionen" card — total number of bookings
- Revenue breakdown by category (name, revenue, count)

**Transaktionen tab:**
- Scrollable list of the 50 most recent transactions
- Each row: product name, NFC UID, time, price (negative prices shown in tertiary colour for refunds)

---

### Users Screen (`users_screen.dart`)
Visible only with `users.*` permissions. Allows creating users, editing display names / passwords, assigning permissions via the permission tree, assigning category access, and applying role templates.

---

### Settings Screen (`settings_screen.dart`)
- Shows the configured backend URL and app version
- **Abmelden** (logout) button with confirmation dialog

---

### Account Screen (`account_screen.dart`)
- Shows the current user's avatar (first letter), display name, and username
- **Abmelden** button

---

## State Management

All cross-screen state is managed with Riverpod providers in `providers/providers.dart`:

| Provider | Type | Purpose |
|---|---|---|
| `authProvider` | `AsyncNotifierProvider` | Logged-in user + token lifecycle |
| `cartProvider` | `NotifierProvider` | Cart items (CartNotifier) |
| `customerProvider` | `StateProvider` | Currently scanned customer |
| `lastBookingProvider` | `StateProvider` | Last booking (for storno button) |
| `selectedCategoryProvider` | `StateProvider` | Active POS category |
| `editModeProvider` | `StateProvider` | Edit mode toggle |
| `currentScreenProvider` | `StateProvider` | Active screen enum |
| `productsProvider` | `FutureProvider.family` | Products per category ID |
| `categoriesProvider` | `FutureProvider` | All visible categories |
