# UC01 — Purchase Flow (Standard Booking)

**Actor:** Stand vendor
**Precondition:** Logged in, has `sales.booking.create` and `categories.view`

---

## Normal Flow

```
1. Vendor opens the POS screen
   → App loads assigned categories via GET /api/products/categories
   → First category is auto-selected; product grid is rendered

2. Guest holds NFC wristband/chip against the reader
   → Mobile:  nfc_manager fires callback with UID immediately
   → Desktop: HID reader types UID into text field; vendor presses Enter
   → App calls GET /api/sales/balance/{nfc_uid}
   → Customer balance and (if new) "Neuer Kunde" badge displayed
   → UID stays visible in the input field

3. Vendor taps products in the grid
   → Each tap adds one unit to the local cart
   → Tapping the same product again increments quantity
   → Cart total and "Rest Guthaben" update in real time
   → If "Rest Guthaben" would go negative, the "Buchen" button is disabled

4. Vendor confirms the cart
   → Taps "Buchen"  (only enabled when balance ≥ cart total)
   → POST /api/sales/ with { nfc_uid, product_ids }
   → Server: BEGIN EXCLUSIVE → read balance → deduct → create sale rows → COMMIT
   → Response: { success: true, new_balance: ..., sale_ids: [...] }
   → App shows the new balance and clears the cart
   → "Letzte Buchung stornieren" button becomes visible
```

---

## Error Cases

| Situation | Server Response | App Reaction |
|---|---|---|
| Unknown NFC UID (first scan) | `balance: 0.0, is_new_customer: true` | Shows red "Neuer Kunde" badge; vendor can still book and take payment in cash |
| Insufficient balance | "Buchen" button is disabled client-side | Vendor must ask the guest to top up first |
| Product inactive since last grid load | `400 "Product X is not available"` | SnackBar error; vendor should reload the grid |
| Product not in active event | `400 "Product does not belong to this event"` | SnackBar error |
| Network timeout | Dio timeout exception | SnackBar error; cart is NOT cleared, vendor can retry |

---

## Cancel (within 5 minutes)

**Actor:** Vendor with `sales.booking.cancel_5min`

```
1. Tap "Letzte Buchung stornieren" (only visible after a successful booking)
   → Dialog shows the booked items, total, and booking time

2. Vendor confirms cancel
   → POST /api/sales/{sale_id}/cancel   (one request per sale row)
   → Server checks: datetime('now') − booked_at ≤ 5 minutes
     · Yes → cancelled=1, balance refunded
     · No  → 403 "Cancel window of 5 minutes has expired"

3. On success:
   → All sale_ids from the last booking are cancelled
   → Customer balance is restored
   → "Letzte Buchung stornieren" button disappears
```

**Unlimited cancel:** Users with `sales.booking.cancel_unlimited` can cancel any booking on the same event with no time restriction. Same endpoint — server skips the time check.
