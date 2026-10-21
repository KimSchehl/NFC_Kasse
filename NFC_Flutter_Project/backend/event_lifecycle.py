"""
Event lifecycle — starting and ending a Fest, Festvorlagen (export/import)
and the CSV export for accounting.

Exactly one event is active per tenant (enforced by a partial unique index,
see migrations.py). The "Intern" event is permanent and always exists; the
kasse runs on it whenever no fest is active, so Guthaben and chips are never
tied to a single fest. Starting a fest switches away from Intern; ending a
fest switches back to it.

Called only through admin_cli.py, i.e. from the admin tool on the server
itself — never over HTTP. Deliberately free of config.py/FastAPI imports:
this runs in a short-lived command-line process, and the printer/bon
settings for a Festvorlage are read straight from config.env/bon.yaml in the
data directory instead of from config.py's import-time constants.

Categories, articles, users and rights belong to the tenant (Veranstalter,
see docs/VERANSTALTER_PLAN.md). A fest only switches categories and
articles on (event_category / event_product), so starting one copies that
selection — never rows — and rights simply stay as they are.
"""

import csv
import io
from datetime import datetime, timezone
from pathlib import Path

import yaml
from dotenv import dotenv_values

import catalog
from config_env_writer import update_config_env
from schemas import EventPreset, EventPresetCategory, EventPresetProduct

PRINTER_KEYS = (
    "PRINTER_TYPE",
    "PRINTER_PORT",
    "PRINTER_BAUDRATE",
    "PRINTER_HOST",
    "PRINTER_LINE_WIDTH",
    "PRINTER_AUTO_CUT",
)
BON_TEXT_KEYS = (
    "BON_FOOTER_TEXT",
    "BON_CASHIER_LABEL",
    "BON_SHOW_EVENT_NAME",
    "BON_SHOW_DATETIME",
    "BON_SHOW_PRICE",
    "BON_SHOW_CASHIER",
)


class EventError(Exception):
    """A rule violation; the message is German and shown to the operator as is."""


def _event_dict(row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "date": row["date"],
        "active": bool(row["active"]),
        "is_intern": bool(row["is_intern"]),
        "chip_deposit": row["chip_deposit"],
        "started_at": row["started_at"],
        "ended_at": row["ended_at"],
    }


def _active_event(db, tenant_id: int):
    row = db.execute(
        "SELECT * FROM event WHERE tenant_id=? AND active=1", (tenant_id,)
    ).fetchone()
    if not row:
        raise EventError("Kein aktives Event gefunden.")
    return row


def _event(db, tenant_id: int, event_id: int):
    row = db.execute(
        "SELECT * FROM event WHERE id=? AND tenant_id=?", (event_id, tenant_id)
    ).fetchone()
    if not row:
        raise EventError("Fest nicht gefunden.")
    return row


# ---------------------------------------------------------------------------
# Overview
# ---------------------------------------------------------------------------

def _seconds_since(db, timestamp: str | None) -> int | None:
    """Age in seconds of a stored timestamp, computed by SQLite itself — same
    clock and same UTC format that wrote it, so the admin tool needs no
    timezone handling to show "vor 12 Sekunden"."""
    if timestamp is None:
        return None
    return db.execute(
        "SELECT CAST(strftime('%s', 'now') - strftime('%s', ?) AS INTEGER)", (timestamp,)
    ).fetchone()[0]


def overview(db, tenant_id: int) -> dict:
    """Every event with its periods (for the CSV export's Zeitraum picker),
    plus what the "Fest beenden" confirmation should warn about."""
    events = []
    for row in db.execute(
        "SELECT * FROM event WHERE tenant_id=? ORDER BY is_intern DESC, id DESC", (tenant_id,)
    ).fetchall():
        event = _event_dict(row)
        event["periods"] = [
            {"id": p["id"], "label": p["label"], "started_at": p["started_at"], "closed_at": p["closed_at"]}
            for p in db.execute(
                "SELECT id, label, started_at, closed_at FROM stats_period WHERE event_id=? ORDER BY started_at",
                (row["id"],),
            ).fetchall()
        ]
        event["sales"] = db.execute(
            "SELECT COUNT(*) FROM sale WHERE event_id=? AND cancelled=0", (row["id"],)
        ).fetchone()[0]
        events.append(event)

    active = _active_event(db, tenant_id)
    # The BAR chip only ever goes negative (cash sales debit it), so
    # balance > 0 is exactly "a guest still has money on this chip".
    chips = db.execute(
        "SELECT COUNT(*) AS n, COALESCE(SUM(balance), 0) AS total FROM customer WHERE tenant_id=? AND balance > 0",
        (tenant_id,),
    ).fetchone()
    # Any money movement at a till counts — bookings as well as top-ups and
    # payouts — so the admin sees whether anyone is still cashing up.
    last_activity = db.execute(
        """
        SELECT MAX(t) FROM (
            SELECT MAX(booked_at) AS t FROM sale WHERE event_id = ?
            UNION ALL
            SELECT MAX(booked_at) FROM topup WHERE event_id = ?
        )
        """,
        (active["id"], active["id"]),
    ).fetchone()[0]
    categories = [
        {
            "id": c["id"],
            "name": c["name"],
            "event_ids": [
                r["event_id"] for r in db.execute(
                    "SELECT event_id FROM event_category WHERE category_id=? ORDER BY event_id", (c["id"],)
                )
            ],
        }
        for c in db.execute(
            "SELECT id, name FROM category WHERE tenant_id=? AND deleted=0 ORDER BY sort_order, id", (tenant_id,)
        ).fetchall()
    ]
    return {
        "events": events,
        "categories": categories,
        "active_event_id": active["id"],
        "last_activity_at": last_activity,
        "seconds_since_last_activity": _seconds_since(db, last_activity),
        "open_print_jobs": db.execute(
            "SELECT COUNT(*) FROM print_job WHERE event_id=? AND status IN ('pending', 'printing')",
            (active["id"],),
        ).fetchone()[0],
        "open_pager_orders": db.execute(
            "SELECT COUNT(*) FROM pager_order WHERE event_id=? AND status='open'", (active["id"],)
        ).fetchone()[0],
        "chips_with_balance": chips["n"],
        "chips_balance_total": chips["total"],
    }


# ---------------------------------------------------------------------------
# Start / end
# ---------------------------------------------------------------------------

def check_can_start(db, tenant_id: int) -> None:
    if not _active_event(db, tenant_id)["is_intern"]:
        raise EventError("Es läuft bereits ein Fest. Bitte zuerst beenden.")


def check_can_end(db, tenant_id: int) -> None:
    if _active_event(db, tenant_id)["is_intern"]:
        raise EventError("Es läuft gerade kein Fest.")


def _activate_from_event(
    db, tenant_id: int, source_event_id: int | None, target_event_id: int, category_ids: list[int] | None,
) -> None:
    """
    Switches on in the new fest what the source event showed: the same
    categories and, within them, the same articles. `category_ids` narrows
    (or, with no source, picks) the categories; a chosen category the source
    didn't show comes with all its articles.
    """
    source_cats = set()
    if source_event_id is not None:
        source_cats = {
            r["category_id"] for r in db.execute(
                "SELECT category_id FROM event_category WHERE event_id=?", (source_event_id,)
            )
        }
    chosen = source_cats if category_ids is None else set(category_ids)
    for category_id in chosen:
        if not catalog.tenant_category(db, tenant_id, category_id):
            raise EventError(f"Warengruppe {category_id} nicht gefunden.")
        if category_id not in source_cats:
            catalog.set_category_in_event(db, target_event_id, category_id, True)
            continue
        db.execute(
            "INSERT OR IGNORE INTO event_category (event_id, category_id) VALUES (?, ?)",
            (target_event_id, category_id),
        )
        db.execute(
            """
            INSERT OR IGNORE INTO event_product (event_id, product_id)
            SELECT ?, ep.product_id FROM event_product ep
            JOIN product p ON p.id = ep.product_id
            WHERE ep.event_id = ? AND p.category_id = ? AND p.deleted = 0
            """,
            (target_event_id, source_event_id, category_id),
        )


def _activate_from_preset(db, tenant_id: int, preset: EventPreset, target_event_id: int) -> None:
    """
    Switches on the preset's categories and articles, matched by name to
    the tenant's own. Missing ones are created from the preset; existing
    ones are left as they are (an article's price is the same in every fest,
    a preset must not silently change it).

    Defensively re-sorts by group_ref presence rather than trusting the
    file's own ordering, since an imported file is opaque input, not
    something this process just produced itself.
    """
    category_id_by_ref: dict[int, int] = {}
    for cat in preset.categories:
        row = db.execute(
            "SELECT id FROM category WHERE tenant_id=? AND name=? AND deleted=0 ORDER BY id LIMIT 1",
            (tenant_id, cat.name),
        ).fetchone()
        category_id = row["id"] if row else db.execute(
            "INSERT INTO category (tenant_id, name, sort_order) VALUES (?, ?, ?)",
            (tenant_id, cat.name, cat.sort_order),
        ).lastrowid
        db.execute(
            "INSERT OR IGNORE INTO event_category (event_id, category_id) VALUES (?, ?)",
            (target_event_id, category_id),
        )
        category_id_by_ref[cat.ref] = category_id

    product_id_by_ref: dict[int, int] = {}
    for p in sorted(preset.products, key=lambda p: p.group_ref is not None):
        if p.category_ref not in category_id_by_ref:
            raise EventError(f"Vorlage fehlerhaft: Artikel „{p.name}“ verweist auf eine unbekannte Warengruppe.")
        category_id = category_id_by_ref[p.category_ref]
        group_id = product_id_by_ref.get(p.group_ref) if p.group_ref is not None else None
        row = db.execute(
            "SELECT id FROM product WHERE category_id=? AND name=? AND deleted=0 "
            + ("AND group_id=? " if group_id is not None else "AND group_id IS NULL ")
            + "ORDER BY id LIMIT 1",
            (category_id, p.name, *([group_id] if group_id is not None else [])),
        ).fetchone()
        product_id = row["id"] if row else db.execute(
            """
            INSERT INTO product
                (category_id, name, price, sort_order, is_payout, is_pfand, exclude_from_stats,
                 points, requires_pager, stock, group_id, color)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                category_id, p.name, p.price, p.sort_order,
                p.is_payout, p.is_pfand, p.exclude_from_stats, p.points,
                p.requires_pager, p.stock, group_id, p.color,
            ),
        ).lastrowid
        product_id_by_ref[p.ref] = product_id
        if group_id is None:
            db.execute(
                "INSERT OR IGNORE INTO event_product (event_id, product_id) VALUES (?, ?)",
                (target_event_id, product_id),
            )


def start_event(
    db,
    *,
    tenant_id: int,
    name: str,
    date: str | None = None,
    chip_deposit: float = 0.0,
    reset_stock: bool = False,
    source_event_id: int | None = None,
    preset: EventPreset | None = None,
    include_articles: bool = True,
    category_ids: list[int] | None = None,
) -> dict:
    """Must run inside get_db(exclusive=True). Takes no safety backup itself
    — the caller does that first, outside the transaction.

    What the new fest shows comes from one source: an earlier event
    (`source_event_id`, also Intern), a preset, or nothing; `category_ids`
    narrows or picks the categories (see _activate_from_event).
    `reset_stock` makes every article switched on in the new fest
    unlimited again — stock belongs to the article, not to the fest."""
    name = name.strip()
    if not name:
        raise EventError("Der Festname darf nicht leer sein.")
    if chip_deposit < 0:
        raise EventError("Der Pfand-Betrag darf nicht negativ sein.")
    if source_event_id is not None and preset is not None:
        raise EventError("Nur eine Artikel-Quelle möglich: entweder ein Fest oder eine Vorlage.")

    check_can_start(db, tenant_id)
    if source_event_id is not None:
        _event(db, tenant_id, source_event_id)

    new_id = db.execute(
        """
        INSERT INTO event (tenant_id, name, active, date, chip_deposit, is_intern, started_at)
        VALUES (?, ?, 0, ?, ?, 0, datetime('now'))
        """,
        (tenant_id, name, date, chip_deposit),
    ).lastrowid

    if preset is not None:
        if include_articles:
            _activate_from_preset(db, tenant_id, preset, new_id)
    else:
        _activate_from_event(db, tenant_id, source_event_id, new_id, category_ids)
    if reset_stock:
        db.execute(
            """
            UPDATE product SET stock = NULL, updated_at = datetime('now')
            WHERE id IN (SELECT product_id FROM event_product WHERE event_id = ?) AND stock IS NOT NULL
            """,
            (new_id,),
        )

    db.execute("UPDATE event SET active=0 WHERE tenant_id=?", (tenant_id,))
    db.execute("UPDATE event SET active=1 WHERE id=?", (new_id,))
    db.execute("INSERT INTO stats_period (event_id, label) VALUES (?, 'Start')", (new_id,))
    return _event_dict(db.execute("SELECT * FROM event WHERE id=?", (new_id,)).fetchone())


def update_active_event(db, *, tenant_id: int, name: str | None = None, chip_deposit: float | None = None) -> dict:
    """
    Changes the running fest's name and/or Pfand — live: every request reads
    the active event anew, so the next bon and the next new chip use it.
    Chips already handed out keep the Pfand they were charged (deposit_paid).
    Intern keeps its name; only its Pfand can change.
    """
    active = _active_event(db, tenant_id)
    if name is not None:
        name = name.strip()
        if not name:
            raise EventError("Der Festname darf nicht leer sein.")
        if active["is_intern"] and name != active["name"]:
            raise EventError("Im internen Betrieb lässt sich der Name nicht ändern.")
        db.execute("UPDATE event SET name=? WHERE id=?", (name, active["id"]))
    if chip_deposit is not None:
        if chip_deposit < 0:
            raise EventError("Der Pfand-Betrag darf nicht negativ sein.")
        db.execute("UPDATE event SET chip_deposit=? WHERE id=?", (chip_deposit, active["id"]))
    # Devices show the fest name from /me — make them reload it.
    catalog.bump_revision(db, tenant_id)
    return _event_dict(db.execute("SELECT * FROM event WHERE id=?", (active["id"],)).fetchone())


def end_event(db, *, tenant_id: int) -> dict:
    """Must run inside get_db(exclusive=True). Returns the ended fest."""
    check_can_end(db, tenant_id)
    active = _active_event(db, tenant_id)
    intern = db.execute(
        "SELECT id FROM event WHERE tenant_id=? AND is_intern=1", (tenant_id,)
    ).fetchone()
    if not intern:
        raise EventError("Internes Event nicht gefunden.")
    intern_id = intern["id"]

    # Close the fest's open period so its revenue stays bounded, same as
    # a manual Tagesabschluss.
    db.execute(
        "UPDATE stats_period SET closed_at = datetime('now') WHERE event_id=? AND closed_at IS NULL",
        (active["id"],),
    )
    # Pager orders belong to physical devices still with a guest; sale,
    # print_job and topup are pure history and need no such cleanup.
    db.execute(
        "UPDATE pager_order SET status='done', done_at=datetime('now') WHERE event_id=? AND status='open'",
        (active["id"],),
    )
    db.execute("UPDATE event SET active=0, ended_at=datetime('now') WHERE id=?", (active["id"],))
    db.execute("UPDATE event SET active=1 WHERE id=?", (intern_id,))
    # Keep Intern's own running period going across Festende instead of
    # fragmenting it every time — only open a new one if it somehow
    # doesn't have one yet.
    open_period = db.execute(
        "SELECT 1 FROM stats_period WHERE event_id=? AND closed_at IS NULL", (intern_id,)
    ).fetchone()
    if not open_period:
        db.execute("INSERT INTO stats_period (event_id, label) VALUES (?, 'Intern')", (intern_id,))
    return _event_dict(db.execute("SELECT * FROM event WHERE id=?", (active["id"],)).fetchone())


# ---------------------------------------------------------------------------
# Festvorlage
# ---------------------------------------------------------------------------

def build_preset(db, *, tenant_id: int, event_id: int, data_dir: Path) -> EventPreset:
    """
    Builds a Festvorlage from the categories and articles switched on in
    event_id plus the current bon.yaml/config.env settings. Only reads —
    safe for any event, active or archived.

    categories/products are keyed by local `ref` indices (not DB ids): base
    articles are ordered before their options so a product's group_ref
    always refers to an already-assigned ref by the time it's needed.
    """
    event = _event(db, tenant_id, event_id)
    categories = db.execute(
        f"""
        SELECT c.id, c.name, c.sort_order FROM category c
        WHERE c.tenant_id = ? AND c.deleted = 0 AND {catalog.CATEGORY_IN_EVENT_SQL}
        ORDER BY c.sort_order, c.id
        """,
        (tenant_id, event_id),
    ).fetchall()
    category_ref = {c["id"]: i for i, c in enumerate(categories)}

    products = [
        p for p in db.execute(
            f"""
            SELECT p.* FROM product p
            WHERE p.deleted = 0 AND {catalog.PRODUCT_IN_EVENT_SQL}
            ORDER BY p.group_id IS NOT NULL, p.sort_order
            """,
            (event_id,),
        ).fetchall()
        if p["category_id"] in category_ref
    ]
    product_ref: dict[int, int] = {}
    preset_products = []
    for i, p in enumerate(products):
        product_ref[p["id"]] = i
        preset_products.append(
            EventPresetProduct(
                ref=i,
                category_ref=category_ref[p["category_id"]],
                name=p["name"],
                price=p["price"],
                sort_order=p["sort_order"],
                is_payout=bool(p["is_payout"]),
                is_pfand=bool(p["is_pfand"]),
                exclude_from_stats=bool(p["exclude_from_stats"]),
                points=p["points"],
                requires_pager=bool(p["requires_pager"]),
                color=p["color"],
                stock=p["stock"],
                group_ref=product_ref.get(p["group_id"]) if p["group_id"] is not None else None,
            )
        )

    bon_yaml = data_dir / "bon.yaml"
    bon_layout = yaml.safe_load(bon_yaml.read_text(encoding="utf-8")) if bon_yaml.exists() else None
    env_path = data_dir / "config.env"
    env = dotenv_values(env_path) if env_path.exists() else {}
    printer = {k: env[k] for k in PRINTER_KEYS if env.get(k) is not None}
    bon_text = {k: env[k] for k in BON_TEXT_KEYS if env.get(k) is not None}

    return EventPreset(
        created_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        source_event_name=event["name"],
        chip_deposit=event["chip_deposit"],
        categories=[
            EventPresetCategory(ref=category_ref[c["id"]], name=c["name"], sort_order=c["sort_order"])
            for c in categories
        ],
        products=preset_products,
        bon_layout=bon_layout or None,
        printer=printer or None,
        bon_text=bon_text or None,
    )


def apply_preset_settings(
    preset: EventPreset,
    data_dir: Path,
    *,
    bon_layout: bool,
    printer: bool,
    bon_text: bool,
) -> bool:
    """Writes the chosen parts of a preset to bon.yaml/config.env. Both are
    read once at service start, so the return value says whether a restart
    is now needed for them to take effect."""
    written = False
    if bon_layout and preset.bon_layout:
        (data_dir / "bon.yaml").write_text(
            yaml.safe_dump(preset.bon_layout, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        written = True
    env_updates: dict[str, str] = {}
    if printer and preset.printer:
        env_updates.update({k: str(v) for k, v in preset.printer.items() if k in PRINTER_KEYS})
    if bon_text and preset.bon_text:
        env_updates.update({k: str(v) for k, v in preset.bon_text.items() if k in BON_TEXT_KEYS})
    if env_updates:
        update_config_env(data_dir / "config.env", env_updates)
        written = True
    return written


# ---------------------------------------------------------------------------
# CSV export (Buchhaltung)
# ---------------------------------------------------------------------------

def bar_chip_uid(data_dir: Path) -> str:
    """Same setting and default as config.py's BAR_CHIP_UID (the virtual chip
    that cash sales via Bon-Druck are booked to), read from config.env
    directly for the reason given in the module docstring."""
    env_path = data_dir / "config.env"
    env = dotenv_values(env_path) if env_path.exists() else {}
    return env.get("BAR_CHIP_UID") or "BAR"


def _money(value: float) -> str:
    # German Excel: decimal comma, no thousands separator.
    return f"{value:.2f}".replace(".", ",")


def _local(ts: str | None, seconds: bool = False) -> str:
    """'JJJJ-MM-TT HH:MM:SS' (already shifted with SQLite's 'localtime')
    -> 'TT.MM.JJJJ HH:MM[:SS]'."""
    if not ts:
        return ""
    d = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")
    return d.strftime("%d.%m.%Y %H:%M:%S" if seconds else "%d.%m.%Y %H:%M")


def _article_kind(row) -> str:
    """Same split as the app's revenue statistics (stats.py get_revenue):
    "Verkauf" is exactly what counts towards Gesamtumsatz there — neither a
    payout nor marked exclude_from_stats. Everything else gets the most
    specific name its flags allow."""
    if row["is_payout"]:
        return "Auszahlung"
    if not row["exclude_from_stats"]:
        return "Verkauf"
    if row["is_pfand"]:
        return "Pfand"
    if row["price"] < 0:
        return "Aufladung"
    return "Nicht im Umsatz"


def export_csv(
    db,
    *,
    tenant_id: int,
    event_id: int,
    period_id: int | None = None,
    bar_chip_uid: str = "BAR",
) -> tuple[str, int]:
    """
    The accounting export for event_id (or one of its periods), laid out for
    German Excel (';', decimal comma, local time) in three blocks:

      1. Buchungen          — every sale row, oldest first
      2. Verkaufte Artikel  — how often each article was sold, for how much
      3. Gesamtstatistik    — Umsatz, Aufladungen, Auszahlungen, Chips, ...

    Everything is limited to the selected range except the figures marked
    "Stand jetzt": those are the live state of all chips, since Guthaben
    belongs to the chip, not to a fest. Returns (csv_text, booking_rows).
    """
    event = _event(db, tenant_id, event_id)
    where, params = "", []
    period = None
    if period_id is not None:
        period = db.execute(
            "SELECT label, started_at, closed_at FROM stats_period WHERE id=? AND event_id=?",
            (period_id, event_id),
        ).fetchone()
        if not period:
            raise EventError("Zeitraum nicht gefunden.")
        where = " AND {col} >= ?"
        params.append(period["started_at"])
        if period["closed_at"]:
            where += " AND {col} <= ?"
            params.append(period["closed_at"])

    sales = db.execute(
        f"""
        SELECT s.id, datetime(s.booked_at, 'localtime') AS booked_local, s.price_at_sale,
               s.cancelled, datetime(s.cancelled_at, 'localtime') AS cancelled_local,
               s.customer_id, cu.nfc_uid, u.username,
               p.id AS product_id, p.name AS product_name, p.price, p.sort_order AS product_sort,
               p.is_payout, p.is_pfand, p.exclude_from_stats,
               c.id AS category_id, c.name AS category_name, c.sort_order AS category_sort
        FROM sale s
        JOIN customer cu ON s.customer_id = cu.id
        JOIN product p ON s.product_id = p.id
        JOIN category c ON p.category_id = c.id
        JOIN user u ON s.booked_by = u.id
        WHERE s.event_id = ? {where.format(col="s.booked_at")}
        ORDER BY s.booked_at, s.id
        """,
        [event_id, *params],
    ).fetchall()
    topups = db.execute(
        f"""
        SELECT customer_id, amount FROM topup
        WHERE event_id = ? AND cancelled = 0 {where.format(col="booked_at")}
        """,
        [event_id, *params],
    ).fetchall()

    out = io.StringIO()
    w = csv.writer(out, delimiter=";", lineterminator="\r\n")

    # --- 1. Buchungen -------------------------------------------------------
    w.writerow(["Nr", "Zeitpunkt", "Chip", "Warengruppe", "Artikel", "Art",
                "Betrag", "Kassierer", "Storniert", "Storniert am"])
    for r in sales:
        w.writerow([
            r["id"], _local(r["booked_local"], seconds=True),
            "Bar (Bon-Druck)" if r["nfc_uid"] == bar_chip_uid else r["nfc_uid"],
            r["category_name"], r["product_name"], _article_kind(r),
            _money(r["price_at_sale"]), r["username"],
            "ja" if r["cancelled"] else "nein", _local(r["cancelled_local"], seconds=True),
        ])

    # --- 2. Verkaufte Artikel ---------------------------------------------
    articles: dict[int, dict] = {}
    for r in sales:
        a = articles.setdefault(r["product_id"], {
            "sort": (r["category_sort"], r["category_id"], r["product_sort"], r["product_id"]),
            "category": r["category_name"], "name": r["product_name"], "kind": _article_kind(r),
            "count": 0, "cancelled": 0, "amount": 0.0,
        })
        if r["cancelled"]:
            a["cancelled"] += 1
        else:
            a["count"] += 1
            a["amount"] += r["price_at_sale"]
    w.writerow([])
    w.writerow(["Verkaufte Artikel"])
    w.writerow(["Warengruppe", "Artikel", "Art", "Anzahl", "Storniert", "Betrag"])
    for a in sorted(articles.values(), key=lambda a: a["sort"]):
        w.writerow([a["category"], a["name"], a["kind"], a["count"], a["cancelled"], _money(a["amount"])])

    # --- 3. Gesamtstatistik -----------------------------------------------
    booked = [r for r in sales if not r["cancelled"]]
    selling = [r for r in booked if _article_kind(r) == "Verkauf"]
    revenue = sum(r["price_at_sale"] for r in selling)
    revenue_bar = sum(r["price_at_sale"] for r in selling if r["nfc_uid"] == bar_chip_uid)
    cancelled = [r for r in sales if r["cancelled"]]
    # Aufladungen arrive two ways: the Aufladen function (topup rows) and
    # Aufladungs-Artikel (negative price, neither Pfand nor Auszahlung).
    # Auszahlungen too: the payout function (negative topup rows) and
    # Auszahlungs-Artikel (one sale row at the paid-out amount, which
    # includes the chip deposit refunded with it).
    topped_up = sum(t["amount"] for t in topups if t["amount"] > 0) + sum(
        -r["price_at_sale"] for r in booked
        if r["price_at_sale"] < 0 and not r["is_pfand"] and not r["is_payout"]
    )
    paid_out = -sum(t["amount"] for t in topups if t["amount"] < 0) + sum(
        r["price_at_sale"] for r in booked if r["is_payout"]
    )
    pfand_sales = [r for r in booked if r["is_pfand"]]
    bar_ids = {r["customer_id"] for r in sales if r["nfc_uid"] == bar_chip_uid}
    used_chips = ({r["customer_id"] for r in sales} | {t["customer_id"] for t in topups}) - bar_ids

    chips = db.execute(
        """
        SELECT
            COUNT(CASE WHEN is_available = 0 THEN 1 END) AS with_guest,
            COUNT(CASE WHEN balance > 0 THEN 1 END) AS with_balance,
            COALESCE(SUM(CASE WHEN balance > 0 THEN balance END), 0) AS balance_total,
            COUNT(CASE WHEN balance < 0 THEN 1 END) AS negative,
            COALESCE(SUM(CASE WHEN balance < 0 THEN balance END), 0) AS negative_total,
            COALESCE(SUM(CASE WHEN is_available = 0 THEN deposit_paid END), 0) AS deposit_total
        FROM customer WHERE tenant_id = ? AND nfc_uid != ?
        """,
        (tenant_id, bar_chip_uid),
    ).fetchone()

    start, end = (period["started_at"], period["closed_at"]) if period else (event["started_at"], event["ended_at"])
    start, end = db.execute("SELECT datetime(?, 'localtime'), datetime(?, 'localtime')", (start, end)).fetchone()
    label = period["label"] if period else "gesamtes Fest"
    span = f"{label} ({_local(start)} – {_local(end) or 'läuft'})" if start else label

    summary = [
        ("Fest", "Intern" if event["is_intern"] else event["name"]),
        ("Zeitraum", span),
        ("Erstellt am", datetime.now().strftime("%d.%m.%Y %H:%M")),
        ("Gesamtumsatz", _money(revenue)),
        ("Verkaufte Artikel (Stück)", len(selling)),
        ("davon bar über Bon-Druck", _money(revenue_bar)),
        ("davon über Chips", _money(revenue - revenue_bar)),
        ("Stornierte Buchungen", len(cancelled)),
        ("Stornierter Betrag", _money(sum(r["price_at_sale"] for r in cancelled))),
        ("Aufgeladen", _money(topped_up)),
        ("Ausgezahlt", _money(paid_out)),
    ]
    if pfand_sales:
        summary.append(("Pfand-Artikel (Saldo)", _money(sum(r["price_at_sale"] for r in pfand_sales))))
    summary += [
        ("Benutzte Chips", len(used_chips)),
        ("Chips beim Gast (Stand jetzt)", chips["with_guest"]),
        ("Chips mit Restguthaben (Stand jetzt)", chips["with_balance"]),
        ("Restguthaben auf Chips (Stand jetzt)", _money(chips["balance_total"])),
    ]
    if chips["negative"]:
        summary += [
            ("Chips im Minus (Stand jetzt)", chips["negative"]),
            ("Betrag im Minus (Stand jetzt)", _money(chips["negative_total"])),
        ]
    summary.append(("Chip-Pfand hinterlegt (Stand jetzt)", _money(chips["deposit_total"])))

    w.writerow([])
    w.writerow(["Gesamtstatistik"])
    w.writerow(["Kennzahl", "Wert"])
    for row in summary:
        w.writerow(row)

    return out.getvalue(), len(sales)
