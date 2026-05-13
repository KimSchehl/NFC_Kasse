# Test Setup

This project has two independent test suites: Flutter unit tests for the app, and pytest integration/unit tests for the FastAPI backend.

---

## Flutter Tests

### Location

```
nfc_kasse_app/
└── test/
    ├── models/
    │   ├── cart_item_test.dart
    │   ├── customer_model_test.dart
    │   └── product_model_test.dart
    ├── providers/
    │   └── cart_notifier_test.dart
    └── utils/
        └── formatters_test.dart
```

### Prerequisites

Flutter SDK must be installed and `flutter pub get` must have been run at least once.

```bash
cd nfc_kasse_app
flutter pub get
```

No additional test packages are needed — `flutter_test` and `flutter_riverpod` are already listed in `pubspec.yaml`.

### Running the tests

```bash
# Run all Flutter tests
cd nfc_kasse_app
flutter test

# Run a single test file
flutter test test/providers/cart_notifier_test.dart

# Run with verbose output (shows each test name)
flutter test --reporter expanded
```

### What is covered

| File | What it tests |
|------|---------------|
| `models/product_model_test.dart` | `fromJson` parsing (all fields, defaults, hex color), `isRefund` flag, `copyWith` (field update, color clear, color preserve) |
| `models/customer_model_test.dart` | `fromJson` parsing (all fields, missing fields), `withBalance` (returns new instance, preserves fields, does not mutate original) |
| `models/cart_item_test.dart` | `subtotal` (single/multi quantity, negative price), `withQuantity` (returns new instance, does not mutate) |
| `providers/cart_notifier_test.dart` | Initial empty state, `addProduct` (new item, quantity increment, separate products, refund), `total` (sum, zero, with refund), `productIds` (quantity expansion — regression for the booking 404 bug), `removeItem`, `clear` |
| `utils/formatters_test.dart` | `formatPrice` (positive, zero, negative, thousands), `formatPriceSigned` (plus/minus/zero prefix), `formatTime` (shape check, invalid input), `formatDate` (shape check, invalid input), `formatDateTime` (combined shape) |

### Notes

- All Flutter tests are **pure unit tests** — they do not require a running backend, a device, or an emulator.
- `formatDate`/`formatTime` assert the shape (`dd.MM.yyyy`, `HH:mm`) rather than an exact value because `DateTime.toLocal()` depends on the system timezone.


---

## Backend Tests

### Location

```
backend/
├── pytest.ini
├── requirements-test.txt
└── tests/
    ├── __init__.py
    ├── conftest.py        ← shared fixtures
    ├── test_auth.py
    ├── test_sales.py
    └── test_schemas.py
```

### Prerequisites

Python 3.11+ and a virtual environment are recommended.

```bash
cd backend

# Install runtime dependencies
pip install -r requirements.txt

# Install test-only dependencies (pytest + httpx)
pip install -r requirements-test.txt
```

`requirements-test.txt` contains:
```
pytest>=8.0.0
httpx>=0.27.0
```

`httpx` is required by Starlette's `TestClient`.

### Running the tests

```bash
# Run all backend tests (from the backend/ directory)
cd backend
pytest

# Run a single file
pytest tests/test_sales.py

# Run with verbose output
pytest -v

# Run a specific test by name
pytest -v -k "test_book_same_product_twice"
```

### What is covered

| File | What it tests |
|------|---------------|
| `test_schemas.py` | Pydantic validators: `BookingRequest` (empty list rejected), `TopupRequest` (zero and negative amount rejected), `UserCreate`/`UserUpdate` (password length enforced, `None` allowed on update) |
| `test_auth.py` | `hash_password` + `verify_password`, `create_access_token` / `_decode_access_token` round-trip, `POST /api/auth/login` (success, wrong password, unknown user), `GET /api/auth/me` (returns permissions, rejects missing token), token refresh (works, cannot be reused) |
| `test_sales.py` | `GET /api/sales/balance/` (new customer flag, existing balance, auth required), `POST /api/sales/` (single product, duplicate IDs correctly counts quantity, nonexistent product → 404, empty list → 422, new customer goes negative, auth required), `POST /api/sales/{id}/cancel` (restores balance, double-cancel → 400, nonexistent → 404) |

### How the test fixtures work (`conftest.py`)

Every test that touches the database gets a **fresh, fully isolated SQLite database** in a temporary directory. This is handled by the `db` fixture:

```
db fixture
│   Creates a temp DB file via pytest's tmp_path
│   Patches database.DB_PATH → temp file   (affects all get_db() calls)
│   Patches init_db.DB_PATH  → temp file   (affects schema creation)
│   Runs init_db() + seed_permissions() + seed_default_data()
│
├── client fixture (depends on db)
│       Creates a FastAPI TestClient pointing at the patched app
│
│   └── auth_headers fixture (depends on client)
│           Logs in as admin / admin and returns Bearer headers
│
├── product_id fixture (depends on db)
│       Inserts a test category ("Test Kategorie") and product ("Bier", 2.50 €)
│       Returns the product's integer ID
│
└── customer_with_balance fixture (depends on db)
        Inserts a customer with NFC UID "TESTUID01" and balance 20.00 €
        Returns the UID string
```

Because `tmp_path` is function-scoped in pytest, each test function gets its own database. Tests cannot affect each other.

The `seed_default_data()` function creates:
- One tenant (`id=1`)
- One active event (`id=1`)
- One admin user (`username=admin`, `password=admin`) with **all** permissions granted

The admin credentials are used by `auth_headers` to authenticate API requests.

### Notes on test isolation

The production database (`kasse.db`) is **never touched** during tests. The `monkeypatch.setattr` in the `db` fixture redirects all database access for the duration of the test and is automatically undone after the test completes.

If you run pytest outside the `backend/` directory, pass the path explicitly:

```bash
pytest NFC_Flutter_Project/backend/tests/
```

---

## Running both suites together

There is no combined runner script, but you can run them back to back:

```bash
# Flutter
cd NFC_Flutter_Project/nfc_kasse_app && flutter test --reporter expanded

# Backend
cd ../backend && pytest -v
```
