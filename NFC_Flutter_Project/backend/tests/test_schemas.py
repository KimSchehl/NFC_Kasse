import pytest
from pydantic import ValidationError

from schemas import BookingRequest, TopupRequest, UserCreate, UserUpdate


def test_booking_rejects_empty_product_ids():
    with pytest.raises(ValidationError):
        BookingRequest(nfc_uid="UID", product_ids=[])


def test_booking_accepts_duplicate_ids():
    req = BookingRequest(nfc_uid="UID", product_ids=[1, 1, 2])
    assert req.product_ids == [1, 1, 2]


def test_topup_rejects_zero_amount():
    with pytest.raises(ValidationError):
        TopupRequest(nfc_uid="UID", amount=0)


def test_topup_rejects_negative_amount():
    with pytest.raises(ValidationError):
        TopupRequest(nfc_uid="UID", amount=-5.0)


def test_topup_accepts_positive_amount():
    req = TopupRequest(nfc_uid="UID", amount=10.0)
    assert req.amount == 10.0


def test_user_create_rejects_short_password():
    with pytest.raises(ValidationError):
        UserCreate(username="user", password="abc")


def test_user_create_accepts_valid_password():
    u = UserCreate(username="user", password="secret123")
    assert u.password == "secret123"


def test_user_update_none_password_is_allowed():
    u = UserUpdate(password=None)
    assert u.password is None


def test_user_update_rejects_short_password():
    with pytest.raises(ValidationError):
        UserUpdate(password="abc")
