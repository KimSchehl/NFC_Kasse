# Database Schema — NFC-Kasse

SQLite (Phase 1) · WAL mode · Foreign Keys ON

---

## Table Overview

| # | Table | Purpose |
|---|---|---|
| 1 | `tenant` | Tenant — locally always id=1, plan='local' |
| 2 | `event` | Event — locally always id=1, active=1 |
| 3 | `user` | POS staff (no guest login in the app) |
| 4 | `permission_node` | Static permission tree (data, not code) |
| 5 | `role_template` | Reusable role presets |
| 6 | `role_template_permission` | Permissions assigned to a template |
| 7 | `user_permission` | Individual permissions per user per event |
| 8 | `category` | Product categories (e.g. "Getränke", "Bar") |
| 9 | `product` | Products with price, sort_order, active/deleted flags |
| 10 | `user_category_access` | Fine-grained category visibility per user |
| 11 | `customer` | Guests with NFC UID and balance |
| 12 | `sale` | Bookings (immutable, append-only) |
| 13 | `topup` | Balance top-ups (separate from purchases) |
| 14 | `refresh_token` | JWT refresh tokens (hashed, revocable) |
| 15 | `user_setting` | Local UI preferences as key/value per user |

---

## Table Details

### tenant
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| name | TEXT | e.g. "Lokal" or organization name |
| plan | TEXT | 'local' \| 'cloud' |
| created_at | TEXT | ISO timestamp |

### event
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| tenant_id | FK → tenant | |
| name | TEXT | e.g. "Weinfest 2026" |
| active | INTEGER | 1 = active (locally always 1) |
| created_at | TEXT | |

### user
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| tenant_id | FK → tenant | |
| username | TEXT | UNIQUE per tenant |
| password_hash | TEXT | bcrypt via passlib |
| display_name | TEXT | Optional display name |
| active | INTEGER | 0 = account locked |
| created_at | TEXT | |

### permission_node
| Column | Type | Description |
|---|---|---|
| id | TEXT PK | e.g. `sales.booking.create` |
| parent_id | FK → permission_node | NULL = root node |
| label | TEXT | German display name for UI |
| node_type | TEXT | 'group' \| 'r' \| 'w' \| 'rw' |
| sort_order | INTEGER | Order in the permission tree |

**Current tree:**
```
sales
  sales.booking
    sales.booking.create           [w]
    sales.booking.cancel_5min      [w]
    sales.booking.cancel_unlimited [w]
  sales.balance
    sales.balance.view             [r]
    sales.balance.topup            [w]
    sales.balance.payout           [w]
products
  products.view                    [r]
  products.create                  [w]
  products.edit                    [w]
  products.set_price               [w]
  products.deactivate              [w]
  products.activate                [w]
  products.delete                  [w]
categories
  categories.view                  [r]   ← gate permission for user_category_access
  categories.create                [w]
  categories.edit                  [w]
  categories.delete                [w]
statistics
  statistics.revenue               [r]
  statistics.transactions          [r]
  statistics.export                [r]
users
  users.view                       [r]
  users.create                     [w]
  users.edit                       [w]
  users.delete                     [w]
  users.manage_permissions         [w]
settings
  settings.local                   [rw]
  settings.event                   [rw]
  settings.system                  [rw]
```

### user_category_access
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| user_id | FK → user | |
| event_id | FK → event | |
| category_id | FK → category | |
| granted_by | FK → user | Who assigned this access |
| granted_at | TEXT | |

**Logic:**
- `categories.view` (permission_node) = user is allowed to see categories at all
- `user_category_access` = which categories they can actually see
- Users with `categories.create` see all categories (admin path in backend code)
- No entries in user_category_access = user sees no categories

### category
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| event_id | FK → event | |
| name | TEXT | e.g. "Bar", "Essen", "Bonkasse" (German content) |
| sort_order | INTEGER | Display order in the app |
| deleted | INTEGER | Soft-delete (0/1) |

### product
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| category_id | FK → category | |
| name | TEXT | e.g. "Bier 0,5L" (German content) |
| price | REAL | In euros |
| sort_order | INTEGER | |
| active | INTEGER | 0 = temporarily disabled |
| deleted | INTEGER | Soft-delete — keeps historical sales valid |
| created_at | TEXT | |

### customer
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| tenant_id | FK → tenant | One wristband works across all events of the same tenant |
| nfc_uid | TEXT | UNIQUE per tenant — balance is NEVER on the chip |
| display_name | TEXT | Future: writable to tag |
| balance | REAL | Balance in euros (always server-side) |
| created_at | TEXT | |

### sale
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| event_id | FK → event | |
| customer_id | FK → customer | |
| product_id | FK → product | |
| price_at_sale | REAL | **Price snapshot** — immutable, independent of future price changes |
| booked_by | FK → user | |
| booked_at | TEXT | Booking timestamp — basis for 5-minute cancel check |
| cancelled | INTEGER | 0 = active, 1 = cancelled |
| cancelled_by | FK → user | |
| cancelled_at | TEXT | |

### topup
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| event_id | FK → event | |
| customer_id | FK → customer | |
| amount | REAL | Amount added (negative = payout) |
| payment_method | TEXT | 'cash' \| 'google_pay' \| 'paypal' |
| booked_by | FK → user | |
| booked_at | TEXT | |
| cancelled | INTEGER | Cancellable |
| cancelled_by | FK → user | |
| cancelled_at | TEXT | |

### refresh_token
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| user_id | FK → user | |
| token_hash | TEXT UNIQUE | SHA-256 of token (never store plaintext) |
| device_info | TEXT | e.g. "Flutter Android" |
| created_at | TEXT | |
| expires_at | TEXT | 30 days from creation |
| revoked | INTEGER | Logout sets revoked=1 |

### user_setting
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| user_id | FK → user | |
| event_id | FK → event | NULL = global setting |
| key | TEXT | e.g. 'grid_columns', 'theme' |
| value | TEXT | Stored as string, parsed by app |

---

## Critical Design Decisions

1. **`sale.price_at_sale`** — Required field. Product prices may change; historical bookings must remain accurate.
2. **Cancel as flag** — `cancelled=1` instead of DELETE. Original row preserved for audit trail.
3. **`user_category_access`** — Fine-grained category visibility. Categories are dynamic, so a dedicated table instead of polluting `permission_node` with dynamic entries.
4. **Soft-delete** — `deleted` flag on `product` and `category`. FK integrity of historical data is preserved.
5. **`active` flag** — Products can be temporarily disabled without deleting.
6. **`tenant_id` everywhere** — Cloud / multi-tenant upgrade without schema change.
7. **WAL mode** — `PRAGMA journal_mode=WAL` allows concurrent reads during event operation.

---

## Indexes

| Index | Table | Columns | Purpose |
|---|---|---|---|
| idx_sale_customer | sale | customer_id | Booking history per customer |
| idx_sale_event | sale | event_id | Statistics per event |
| idx_sale_booked_at | sale | booked_at | Time-range queries |
| idx_topup_customer | topup | customer_id | Top-ups per customer |
| idx_customer_nfc | customer | nfc_uid | NFC UID lookup on every booking |
| idx_user_permission | user_permission | user_id, event_id | Permission check |
| idx_user_category_access | user_category_access | user_id, event_id | Category visibility check |
| idx_product_category | product | category_id | Products per category |
| idx_refresh_token | refresh_token | token_hash | Token validation |
