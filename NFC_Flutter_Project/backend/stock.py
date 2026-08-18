"""
Shared stock-tracking logic for the two places that create `sale` rows:
sales.py's create_booking() (normal NFC-chip booking) and printer.py's
print_bon() (the "no chip scanned" cash-sale / Bar-Verkauf flow). Both must
validate and decrement stock identically, so the logic lives here once
instead of being duplicated across two router modules.
"""

from collections import Counter

from fastapi import HTTPException

LOW_STOCK_THRESHOLD = 10  # matches sales.py's CANCEL_WINDOW_MINUTES style — a local constant, not a config.env setting


def check_stock_and_decrement(db, product_ids_flat: list[int], products_by_id: dict) -> list[dict]:
    """
    Validates sufficient stock for every product being booked and decrements
    it. `product_ids_flat` may contain repeats (one entry per unit — quantity
    is the count of repeats). `products_by_id` values must support `[]`
    indexing for `id`, `name`, `stock` (a sqlite3.Row or dict both work; never
    use `.get()` here so either works identically).

    Must be called inside the same `get_db(exclusive=True)` transaction as
    the sale-row inserts — a later failure elsewhere in that transaction (e.g.
    a permission check) rolls the whole transaction back automatically
    (see database.py's get_db), which undoes this decrement too. That's what
    makes it safe to call this before later checks, not just after.

    Two passes: first validate every stock-tracked product has enough
    quantity available, THEN decrement — so a batch that fails validation
    partway through never partially decrements anything.

    Returns a list of {"product_name", "remaining"} for any stock-tracked
    product whose stock is now <= LOW_STOCK_THRESHOLD, for the caller to
    surface as a low-stock warning to the booking device.
    """
    qty_by_product = Counter(product_ids_flat)

    for product_id, qty in qty_by_product.items():
        p = products_by_id[product_id]
        stock = p["stock"]
        if stock is None:
            continue
        if stock <= 0:
            raise HTTPException(status_code=400, detail=f"Artikel '{p['name']}' ist ausverkauft")
        if qty > stock:
            raise HTTPException(
                status_code=400,
                detail=f"Nicht genug Bestand für '{p['name']}' (nur noch {stock} verfügbar)",
            )

    warnings = []
    for product_id, qty in qty_by_product.items():
        p = products_by_id[product_id]
        if p["stock"] is None:
            continue
        new_stock = p["stock"] - qty
        db.execute(
            "UPDATE product SET stock=?, updated_at=datetime('now') WHERE id=?",
            (new_stock, product_id),
        )
        if new_stock <= LOW_STOCK_THRESHOLD:
            warnings.append({"product_name": p["name"], "remaining": new_stock})

    return warnings
