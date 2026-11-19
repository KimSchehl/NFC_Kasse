"""Customer display: booking confirmation pushed by the server."""
import pytest

from routers import display


@pytest.fixture(autouse=True)
def _clear_display_state():
    display._states.clear()
    yield
    display._states.clear()


def test_booking_pushes_confirmation_with_remaining_balance(client, auth_headers, product_id, customer_with_balance):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id]},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    conf = display._states["admin"]["confirmation"]
    assert conf["kind"] == "booking"
    assert conf["balance"] == pytest.approx(resp.json()["new_balance"])


def test_confirmation_survives_the_apps_clearing_push(client, auth_headers, product_id, customer_with_balance):
    client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id]},
        headers=auth_headers,
    )
    conf = display._states["admin"]["confirmation"]
    # The app clears chip and cart right after the booking.
    client.post("/api/display/update", json={"items": []}, headers=auth_headers)
    assert display._states["admin"]["confirmation"] == conf


def test_old_confirmation_is_dropped(client, auth_headers, product_id, customer_with_balance):
    client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": [product_id]},
        headers=auth_headers,
    )
    display._states["admin"]["confirmation"]["at"] -= display.CONFIRM_HOLD_SECONDS + 1
    client.post("/api/display/update", json={"items": []}, headers=auth_headers)
    assert display._states["admin"]["confirmation"] is None


def test_failed_booking_pushes_no_confirmation(client, auth_headers, customer_with_balance):
    resp = client.post(
        "/api/sales/",
        json={"nfc_uid": customer_with_balance, "product_ids": ["00000000-0000-0000-0000-000000000000"]},
        headers=auth_headers,
    )
    assert resp.status_code == 404
    assert "admin" not in display._states
