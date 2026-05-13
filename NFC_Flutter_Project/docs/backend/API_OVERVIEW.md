# Backend API — Overview

FastAPI · Python 3.12 · JWT Auth · Swagger UI at `/docs`

---

## Base URL

```
Local dev:   http://localhost:8000
Real device: http://192.168.1.1:8000   (server's LAN IP, configurable)
Swagger UI:  http://<host>:8000/docs   ← All endpoints testable in browser
ReDoc:       http://<host>:8000/redoc
Health:      GET /health               ← Returns {"status": "ok"}
```

---

## Authentication

All protected endpoints require a bearer token in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

Tokens are obtained via `POST /api/auth/login`. The access token is valid for **24 hours**; the refresh token for **30 days**.

---

## Router Overview

| Router | Prefix | File |
|---|---|---|
| Auth | `/api/auth` | `routers/auth.py` |
| Products | `/api/products` | `routers/products.py` |
| Sales | `/api/sales` | `routers/sales.py` |
| Top-up | `/api/topup` | `routers/topup.py` |
| Users | `/api/users` | `routers/users.py` |
| Stats | `/api/stats` | `routers/stats.py` |

---

## `/api/auth` — Authentication

### POST `/api/auth/login`
No auth header required.

**Request:**
```json
{ "username": "admin", "password": "admin" }
```
**Response `200`:**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "a3f8...",
  "token_type": "bearer",
  "expires_in": 3600
}
```

---

### POST `/api/auth/refresh`
Exchange a refresh token for a new token pair. Refresh tokens are single-use (rotation).

**Request:**
```json
{ "refresh_token": "a3f8..." }
```
**Response `200`:** Same structure as login.

---

### POST `/api/auth/logout`
Revokes the refresh token server-side. Idempotent — no error if token is already revoked.

**Request:**
```json
{ "refresh_token": "a3f8..." }
```
**Response `204`:** No content.

---

### GET `/api/auth/me`
Returns the current user's profile, permissions, and category access.

**Response `200`:**
```json
{
  "id": 1,
  "username": "admin",
  "display_name": "Administrator",
  "permissions": [
    "sales.booking.create",
    "sales.booking.cancel_5min",
    "categories.view",
    "..."
  ],
  "categories": [
    {
      "category_id": 1,
      "category_name": "Bar",
      "can_edit": true,
      "can_delete": true,
      "can_deactivate": true
    }
  ]
}
```

---

## `/api/products` — Categories & Products

### GET `/api/products/categories`
Permission: `categories.view`

Returns the categories visible to the current user. Users with any of `categories.create/edit/delete` receive all categories with full access flags. Other users receive only categories explicitly assigned via `user_category_access`.

**Response `200`:**
```json
[
  {
    "id": 1,
    "name": "Bar",
    "sort_order": 1,
    "can_edit": false,
    "can_delete": false,
    "can_deactivate": true
  }
]
```

---

### POST `/api/products/categories`
Permission: `categories.create`

**Request:**
```json
{ "name": "Essen", "sort_order": 3 }
```
**Response `200`:** `CategoryWithPermissionsResponse`

---

### PUT `/api/products/categories/{id}`
Permission: `categories.edit` (global) **or** `can_edit=true` on `user_category_access`.

**Request:**
```json
{ "name": "Neue Bezeichnung", "sort_order": 2 }
```

---

### DELETE `/api/products/categories/{id}`
Permission: `categories.delete` (global) **or** `can_delete=true` on `user_category_access`.  
Soft-delete: sets `deleted=1`. Historical sales remain intact.

---

### GET `/api/products/?category_id={id}`
Permission: `categories.view` + category must be visible to the user.

**Response `200`:**
```json
[
  {
    "id": 3,
    "name": "Bier 0,5L",
    "price": 3.50,
    "category_id": 1,
    "sort_order": 1,
    "active": true,
    "color": "#A5D6A7"
  }
]
```

---

### POST `/api/products/`
Permission: `can_edit=true` for the target category (or global category manager).

**Request:**
```json
{
  "name": "Bier 0,5L",
  "price": 3.50,
  "category_id": 1,
  "sort_order": 1,
  "color": "#A5D6A7"
}
```

> Negative prices are valid for refund/top-up products (e.g. Pfand Rückgabe, Aufladen).

---

### PUT `/api/products/{id}`
Permission: `can_edit=true` for the product's category.

**Request** (all fields optional):
```json
{ "name": "Bier groß", "price": 4.00, "sort_order": 2, "color": null }
```

> Sending `"color": null` explicitly clears the custom color.

---

### PATCH `/api/products/{id}/active`
Permission: `can_deactivate=true` for the product's category.

**Request:**
```json
{ "active": false }
```

---

### DELETE `/api/products/{id}`
Permission: `can_delete=true` for the product's category.  
Soft-delete: sets `deleted=1`.

---

## `/api/sales` — Bookings

### GET `/api/sales/balance/{nfc_uid}`
Permission: `sales.balance.view`

Returns the current balance for a guest wristband. Creates no records — read-only.

**Response `200`:**
```json
{ "nfc_uid": "04ABCDEF", "balance": 12.50, "is_new_customer": false }
```

If the UID is not yet in the database, `is_new_customer: true` and `balance: 0.0` are returned (no new row is created at this point).

---

### POST `/api/sales/`
Permission: `sales.booking.create`

Creates a booking for one or more products. The active event is determined server-side from the authenticated user's tenant — **no `event_id` in the request**.

The same product ID may appear multiple times in `product_ids` to represent quantity (e.g. `[1, 1]` = two units of product 1).

If the NFC UID is unknown, a new customer row is created automatically with a starting balance of `0.00 €`. Bookings that result in a negative balance are permitted.

All operations (balance read → deduct → sale rows) execute inside a single `BEGIN EXCLUSIVE` transaction.

**Request:**
```json
{
  "nfc_uid": "04ABCDEF",
  "product_ids": [3, 3, 7]
}
```

**Response `201`:**
```json
{
  "success": true,
  "new_balance": 5.50,
  "sale_ids": [101, 102, 103]
}
```

**Error responses:**

| Code | Reason |
|---|---|
| `400` | One or more products do not belong to the active event, or a product is inactive |
| `403` | Permission missing |
| `404` | One or more product IDs do not exist |
| `422` | `product_ids` is empty |

---

### POST `/api/sales/{sale_id}/cancel`
Permission: `sales.booking.cancel_5min`

Cancels a single sale row and refunds the price to the customer's balance. The server checks `datetime('now') - booked_at ≤ 5 minutes` unless the user also has `sales.booking.cancel_unlimited`.

**Response `200`:**
```json
{ "success": true, "refunded_amount": 3.50 }
```

**Error responses:**

| Code | Reason |
|---|---|
| `400` | Sale is already cancelled |
| `403` | 5-minute window has expired |
| `404` | Sale not found in the active event |

---

## `/api/topup` — Balance Top-up

### POST `/api/topup/`
Permission: `sales.balance.topup`

Adds a positive amount to a customer's balance. Creates a row in the `topup` table (separate from `sale`).

**Request:**
```json
{
  "nfc_uid": "04ABCDEF",
  "amount": 20.00,
  "payment_method": "cash"
}
```
> `amount` must be `> 0`. `payment_method` defaults to `"cash"`.

**Response `200`:**
```json
{ "success": true, "new_balance": 32.50 }
```

---

### POST `/api/topup/payout/{nfc_uid}`
Permission: `sales.balance.payout`

Pays out the entire remaining balance in cash and sets the balance to `0.00`. Creates a negative-amount topup row for audit purposes.

**Response `200`:**
```json
{ "success": true, "paid_out": 12.50, "new_balance": 0.0 }
```

---

## `/api/users` — User Management

All endpoints require bearer token. Permission checks noted per endpoint.

### GET `/api/users/`
Permission: `users.view` — Returns all users for the tenant.

### POST `/api/users/`
Permission: `users.create`

**Request:**
```json
{ "username": "vendor1", "password": "secret123", "display_name": "Anna" }
```
> Password must be ≥ 6 characters.

### PUT `/api/users/{id}`
Permission: `users.edit` — Updates username, password, or display name (all optional).

### DELETE `/api/users/{id}`
Permission: `users.delete` — Sets `active=0` (soft-delete). User cannot log in after this.

### GET `/api/users/{id}/permissions`
Permission: `users.manage_permissions` — Returns current permissions and category access.

### PUT `/api/users/{id}/permissions`
Permission: `users.manage_permissions` — Replaces all `user_permission` rows for the user on the active event.

**Request:**
```json
{ "permission_ids": ["sales.booking.create", "sales.booking.cancel_5min", "categories.view"] }
```

### PUT `/api/users/{id}/categories`
Permission: `users.manage_permissions` — Replaces all `user_category_access` rows.

**Request:**
```json
{
  "categories": [
    { "category_id": 1, "can_edit": false, "can_delete": false, "can_deactivate": true },
    { "category_id": 2, "can_edit": true,  "can_delete": false, "can_deactivate": true }
  ]
}
```

### GET `/api/users/role-templates`
No additional permission — returns the predefined role templates.

### POST `/api/users/{id}/apply-template/{template_id}`
Permission: `users.manage_permissions` — Replaces the user's permissions with those from the template.

---

## `/api/stats` — Statistics

### GET `/api/stats/revenue`
Permission: `statistics.revenue`

**Response `200`:**
```json
{
  "total_revenue": 1234.50,
  "total_transactions": 87,
  "by_category": [
    { "category_name": "Bar", "revenue": 890.00, "transaction_count": 56 }
  ],
  "period_start": null,
  "period_end": null
}
```

### GET `/api/stats/transactions`
Permission: `statistics.transactions` — Returns the 50 most recent transactions.

### GET `/api/stats/export`
Permission: `statistics.export` — Returns a CSV download of all transactions.

---

## Standard Error Codes

| Code | Meaning |
|---|---|
| `400` | Bad request (business logic violation) |
| `401` | Not authenticated or token expired |
| `403` | Forbidden — permission missing or time window expired |
| `404` | Resource not found |
| `409` | Conflict — e.g. username already taken |
| `422` | Pydantic validation error — malformed request body |
