# UC02 — Balance Top-up

**Actor:** Bonkasse staff  
**Precondition:** Logged in, has `sales.balance.topup`

---

## Flow

```
1. Staff opens Top-up screen

2. Guest holds NFC chip against reader → UID detected
   → GET /api/sales/balance/{nfc_uid}
   → Unknown UID: new customer is created on first top-up

3. Staff enters amount (e.g. 20.00 €)
   → Select payment method: Bar (default)

4. Confirm "LOAD"
   → POST /api/topup/ with { nfc_uid, amount, payment_method, event_id }
   → Server: balance += amount, insert topup row
   → Response: { success: true, new_balance: 25.00 }

5. App shows new balance
```

---

## Payout (return balance to guest)

**Actor:** Bonkasse staff with `sales.balance.payout`

```
1. Scan NFC chip → display current balance
2. "PAYOUT" → confirmation dialog with current balance amount
3. POST /api/topup/payout/{nfc_uid}
   → Server inserts a topup row with negative amount → balance = 0
4. Staff pays out the amount in cash
```

> **Note:** A payout creates a `topup` row with a negative amount — full audit trail is preserved.
