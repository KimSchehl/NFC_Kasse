"""
Pydantic request/response models for the NFC-Kasse API.

Design notes:
- Negative product prices are intentional (Pfand Rückgabe, Aufladen products)
  and are NOT restricted here or in the products router.
- `color` fields on products use optional `str | None`: None means "no custom
  color" (the Flutter tile falls back to the theme default).
- Full replace semantics are used for permissions and category access:
  `PUT /users/{id}/permissions` deletes all existing rows then inserts the new
  set in a single transaction.
"""

from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds


class RefreshRequest(BaseModel):
    refresh_token: str


class CategoryPermissionResponse(BaseModel):
    category_id: int
    category_name: str
    can_book: bool
    can_storno_5min: bool
    can_storno_unlimited: bool
    can_create_article: bool
    can_edit_article: bool
    can_deactivate_article: bool
    can_delete_article: bool


class MeResponse(BaseModel):
    id: int
    username: str
    display_name: str | None
    permissions: list[str]
    categories: list[CategoryPermissionResponse]


# ---------------------------------------------------------------------------
# Categories
# ---------------------------------------------------------------------------

class CategoryWithPermissionsResponse(BaseModel):
    id: int
    name: str
    sort_order: int
    can_book: bool
    can_storno_5min: bool
    can_storno_unlimited: bool
    can_create_article: bool
    can_edit_article: bool
    can_deactivate_article: bool
    can_delete_article: bool


class CategoryResponse(BaseModel):
    id: int
    name: str
    sort_order: int


class CategoryCreate(BaseModel):
    name: str
    sort_order: int = 0


class CategoryUpdate(BaseModel):
    name: str | None = None
    sort_order: int | None = None


# ---------------------------------------------------------------------------
# Products
# Prices may be negative (Pfand Rückgabe, Aufladen) — no validator restriction
# ---------------------------------------------------------------------------

class ProductResponse(BaseModel):
    id: int
    name: str
    price: float
    category_id: int
    sort_order: int
    active: bool
    color: str | None = None
    is_payout: bool = False


class ProductCreate(BaseModel):
    name: str
    price: float
    category_id: int
    sort_order: int = 0
    color: str | None = None
    is_payout: bool = False


class ProductUpdate(BaseModel):
    name: str | None = None
    price: float | None = None
    sort_order: int | None = None
    color: str | None = None  # explicitly sent None clears the color
    is_payout: bool | None = None


class ProductActiveUpdate(BaseModel):
    active: bool


# ---------------------------------------------------------------------------
# Sales
# ---------------------------------------------------------------------------

class BookingRequest(BaseModel):
    nfc_uid: str
    product_ids: list[int]

    @field_validator("product_ids")
    @classmethod
    def must_not_be_empty(cls, v: list[int]) -> list[int]:
        if not v:
            raise ValueError("product_ids must not be empty")
        return v


class BookingResponse(BaseModel):
    success: bool
    new_balance: float
    sale_ids: list[int]
    chip_deposit_applied: float = 0.0   # Pfand deducted on new-customer issuance
    chip_deposit_refunded: float = 0.0  # Pfand returned on payout


class BalanceResponse(BaseModel):
    nfc_uid: str
    balance: float
    is_new_customer: bool
    chip_deposit: float = 0.0  # configured deposit amount (always present)


class CancelResponse(BaseModel):
    success: bool
    refunded_amount: float


# ---------------------------------------------------------------------------
# Topup (manual cash topup / payout — separate from product-based Aufladen)
# ---------------------------------------------------------------------------

class TopupRequest(BaseModel):
    nfc_uid: str
    amount: float
    payment_method: str = "cash"

    @field_validator("amount")
    @classmethod
    def amount_must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Amount must be > 0")
        return v


class TopupResponse(BaseModel):
    success: bool
    new_balance: float


class PayoutResponse(BaseModel):
    success: bool
    paid_out: float
    new_balance: float


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------

class UserResponse(BaseModel):
    id: int
    username: str
    display_name: str | None
    active: bool


class UserCreate(BaseModel):
    username: str
    password: str
    display_name: str | None = None

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str) -> str:
        if len(v) < 6:
            raise ValueError("Password must be at least 6 characters")
        return v


class UserUpdate(BaseModel):
    username: str | None = None
    password: str | None = None
    display_name: str | None = None

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str | None) -> str | None:
        if v is not None and len(v) < 6:
            raise ValueError("Password must be at least 6 characters")
        return v


class UserPermissionsResponse(BaseModel):
    user: UserResponse
    permissions: list[str]
    categories: list[CategoryPermissionResponse]


class PermissionsUpdate(BaseModel):
    permission_ids: list[str]


class CategoryAccessItem(BaseModel):
    category_id: int
    can_book: bool = False
    can_storno_5min: bool = False
    can_storno_unlimited: bool = False
    can_create_article: bool = False
    can_edit_article: bool = False
    can_deactivate_article: bool = False
    can_delete_article: bool = False


class CategoryAccessUpdate(BaseModel):
    categories: list[CategoryAccessItem]


class RoleTemplateResponse(BaseModel):
    id: int
    name: str
    description: str | None
    permission_ids: list[str]


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

class CategoryRevenue(BaseModel):
    category_name: str
    revenue: float
    transaction_count: int


class RevenueResponse(BaseModel):
    total_revenue: float
    total_transactions: int
    by_category: list[CategoryRevenue]
    period_start: str | None
    period_end: str | None


class TransactionItem(BaseModel):
    id: int
    booked_at: str
    nfc_uid: str
    product_name: str
    price_at_sale: float
    category_name: str
    booked_by_username: str
    cancelled: bool


class TransactionListResponse(BaseModel):
    items: list[TransactionItem]
    total: int
