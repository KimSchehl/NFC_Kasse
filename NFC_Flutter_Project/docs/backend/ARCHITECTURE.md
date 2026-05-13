# Backend Architecture

FastAPI · Python 3.12 · SQLite (Phase 1)

---

## File Structure

```
backend/
├── init_db.py          — Create DB schema + seed data
├── database.py         — Central DB connection (context manager)
├── dependencies.py     — get_current_user(), require_permission()
├── main.py             — FastAPI app, CORS, router registration
├── models.py           — Pydantic request/response models
└── routers/
    ├── auth.py         — Login, refresh, logout, /me
    ├── users.py        — User CRUD + permission management
    ├── products.py     — Products + categories CRUD
    ├── sales.py        — Booking + cancel + balance query
    ├── topup.py        — Balance top-up + payout
    └── stats.py        — Revenue, transactions, CSV export
```

---

## database.py — Central DB Connection

```python
import sqlite3
import os
from contextlib import contextmanager

DB_PATH = os.environ.get("DB_PATH", "kasse.db")

@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row   # results accessible as dict-like objects
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
```

---

## dependencies.py — Auth & Permission Checks

```python
def get_current_user(token: str = Depends(oauth2_scheme)):
    payload = decode_jwt(token)       # raises 401 on invalid/expired token
    with get_db() as db:
        user = db.execute(
            "SELECT * FROM user WHERE id=? AND active=1", (payload["sub"],)
        ).fetchone()
    if not user:
        raise HTTPException(401, "User not found or inactive")
    return user

def require_permission(permission_id: str):
    def checker(
        current_user = Depends(get_current_user),
        event_id: int = Query(...)
    ):
        with get_db() as db:
            has_perm = db.execute("""
                SELECT 1 FROM user_permission
                WHERE user_id=? AND event_id=? AND permission_id=?
            """, (current_user["id"], event_id, permission_id)).fetchone()
        if not has_perm:
            raise HTTPException(403, f"Permission '{permission_id}' required")
    return checker

# Usage in router:
@router.post("/sales/")
def create_sale(..., _=Depends(require_permission("sales.booking.create"))):
    ...
```

---

## JWT — Token Concept

| Token | Lifetime | Stored |
|---|---|---|
| Access Token | 60 minutes | Flutter memory only (flutter_secure_storage) |
| Refresh Token | 30 days | Hashed in DB (refresh_token.token_hash) |

**Flow:**
1. Login → access token + refresh token
2. Every API request: `Authorization: Bearer <access_token>`
3. Access token expired → `POST /api/auth/refresh` with refresh token
4. Logout → refresh token marked `revoked=1` in DB

**Required packages:**
```
python-jose[cryptography]   — JWT encode/decode
passlib[bcrypt]             — Password hashing
```

---

## Transaction Safety for Bookings

Bookings must be atomic (balance check + deduction in one transaction):

```python
# In routers/sales.py
with get_db() as db:
    # EXCLUSIVE prevents concurrent bookings on the same customer
    db.execute("BEGIN EXCLUSIVE")
    customer = db.execute(
        "SELECT balance FROM customer WHERE nfc_uid=? AND tenant_id=?",
        (nfc_uid, tenant_id)
    ).fetchone()
    if customer["balance"] < total_price:
        raise HTTPException(400, "Insufficient balance")
    db.execute(
        "UPDATE customer SET balance = balance - ? WHERE nfc_uid=?",
        (total_price, nfc_uid)
    )
    # INSERT sale rows...
```

---

## CORS Configuration

```python
# Local network only — never allow_origins=["*"] in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://192.168.1.1:8000", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

---

## Mistakes from the Old Codebase — Not Repeated

| Old Problem | New Solution |
|---|---|
| Passwords in plaintext | passlib + bcrypt |
| Admin check via `username.startsWith('admin')` | Permission system |
| `sqlite3.connect("kasse.db")` scattered everywhere | `database.py` context manager |
| `allow_origins=["*"]` | Local IPs only |
| No Pydantic models on endpoints | Every endpoint has request/response schema |
| Copy-pasted helper functions | `dependencies.py` |
