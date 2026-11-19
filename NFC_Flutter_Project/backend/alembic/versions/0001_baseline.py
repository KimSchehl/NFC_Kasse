"""Baseline schema (PostgreSQL)

Ownership (see docs/VERANSTALTER_PLAN.md):
- tenant = Veranstalter. Owns users, rights, categories, articles and chips.
- event = one Fest (or the permanent "Intern" event) of a tenant. Owns only
  what happened during it (sales, top-ups, periods, pagers, print jobs) plus
  which of the tenant's categories/articles are switched on for it
  (event_category / event_product).
- permission_node as data table, not hardcoded enum in code.

Types: keys UUID (v7, time-ordered — rows from different installations
never collide, so a Veranstalter can move between local and cloud by
copying its rows), money NUMERIC(10,2), times TIMESTAMPTZ (UTC), flags
SMALLINT 0/1 — database.py hands them to the code as str, float,
"YYYY-MM-DD HH:MM:SS" and int.

Moving a Veranstalter between local and cloud (before/after a fest, see
docs/POSTGRES_PLAN.md) and row-level security need tenant_id in every
Veranstalter table; a trigger fills it from the parent row, so INSERTs need
not name it. updated_at is set by trigger on every UPDATE.

Revision ID: 0001
Revises:
"""

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

ID = "UUID PRIMARY KEY DEFAULT uuidv7()"

STATEMENTS = [
    # TENANT = Veranstalter. Local: one or more used one after another;
    # exactly one is active (chosen in the admin tool), only its users can
    # log in. Cloud: many tenants active at the same time.
    f"""
    CREATE TABLE tenant (
        id          {ID},
        name        TEXT        NOT NULL,
        plan        TEXT        NOT NULL DEFAULT 'local',  -- 'local' | 'cloud'
        active      SMALLINT    NOT NULL DEFAULT 0,        -- local: the one Veranstalter in use
        catalog_rev INTEGER     NOT NULL DEFAULT 0,        -- bumped on every catalog write, devices reload on change (/health)
        created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    )""",
    # EVENT — exactly one active per tenant (partial unique index below)
    f"""
    CREATE TABLE event (
        id           {ID},
        tenant_id    UUID       NOT NULL REFERENCES tenant(id),
        name         TEXT          NOT NULL,
        active       SMALLINT      NOT NULL DEFAULT 1,
        date         TEXT,
        chip_deposit NUMERIC(10,2) NOT NULL DEFAULT 0,  -- Pfand for new chip issues during this event
        is_intern    SMALLINT      NOT NULL DEFAULT 0,  -- 1 = the permanent "Intern" event (no fest running)
        started_at   TIMESTAMPTZ,
        ended_at     TIMESTAMPTZ,
        created_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
    )""",
    # APP_USER — Kassen-Benutzer ("user" is reserved in PostgreSQL).
    # password_hash: bcrypt (NEVER plaintext)
    f"""
    CREATE TABLE app_user (
        id            {ID},
        tenant_id     UUID     NOT NULL REFERENCES tenant(id),
        username      TEXT        NOT NULL,
        password_hash TEXT        NOT NULL,
        display_name  TEXT,
        active        SMALLINT    NOT NULL DEFAULT 1,
        deleted       SMALLINT    NOT NULL DEFAULT 0,
        created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE (tenant_id, username)
    )""",
    # PERMISSION NODE — extensible permission tree; new permissions = new
    # rows. parent_id NULL = root. node_type: 'group' | 'r' | 'w' | 'rw'
    """
    CREATE TABLE permission_node (
        id         TEXT    PRIMARY KEY,   -- e.g. 'guthaben.topup'
        parent_id  TEXT    REFERENCES permission_node(id),
        label      TEXT    NOT NULL,      -- display label (German for UI)
        node_type  TEXT    NOT NULL DEFAULT 'w',
        sort_order INTEGER NOT NULL DEFAULT 0
    )""",
    # ROLE TEMPLATE — reusable role presets (e.g. "Standverkäufer")
    f"""
    CREATE TABLE role_template (
        id          {ID},
        tenant_id   UUID NOT NULL REFERENCES tenant(id),
        name        TEXT    NOT NULL,
        description TEXT,
        UNIQUE (tenant_id, name)
    )""",
    """
    CREATE TABLE role_template_permission (
        role_template_id UUID NOT NULL REFERENCES role_template(id),
        permission_id    TEXT    NOT NULL REFERENCES permission_node(id),
        PRIMARY KEY (role_template_id, permission_id)
    )""",
    # USER PERMISSION — global permissions of a user, valid in every event
    # of the user's tenant. Each row = one checked leaf node in the tree.
    f"""
    CREATE TABLE user_permission (
        id            {ID},
        user_id       UUID     NOT NULL REFERENCES app_user(id),
        permission_id TEXT        NOT NULL REFERENCES permission_node(id),
        granted_by    UUID     REFERENCES app_user(id),
        granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE (user_id, permission_id)
    )""",
    # CATEGORY & PRODUCT — owned by the tenant, switched on per event.
    # deleted (soft-delete): historical sales remain valid.
    f"""
    CREATE TABLE category (
        id         {ID},
        tenant_id  UUID  NOT NULL REFERENCES tenant(id),
        name       TEXT     NOT NULL,
        sort_order INTEGER  NOT NULL DEFAULT 0,
        color      TEXT,    -- default colour '#RRGGBB'; NULL = theme. Per-user overrides: user_preference_store
        deleted    SMALLINT NOT NULL DEFAULT 0
    )""",
    f"""
    CREATE TABLE product (
        id                 {ID},
        category_id        UUID       NOT NULL REFERENCES category(id),
        name               TEXT          NOT NULL,
        price              NUMERIC(10,2) NOT NULL,
        sort_order         INTEGER       NOT NULL DEFAULT 0,
        active             SMALLINT      NOT NULL DEFAULT 1,  -- temporarily not bookable (greyed out), in every event
        deleted            SMALLINT      NOT NULL DEFAULT 0,  -- soft-delete, keeps historical sales valid
        is_payout          SMALLINT      NOT NULL DEFAULT 0,  -- pays out the whole balance
        exclude_from_stats SMALLINT      NOT NULL DEFAULT 0,  -- exclude from revenue statistics
        is_pfand           SMALLINT      NOT NULL DEFAULT 0,  -- deposit article: no guthaben.topup needed, never revenue
        color              TEXT,                              -- default button colour '#RRGGBB'; NULL = theme
        points             INTEGER       NOT NULL DEFAULT 0,  -- leaderboard points per booking
        requires_pager     SMALLINT      NOT NULL DEFAULT 0,  -- needs a kitchen pager when booked
        stock              INTEGER,                           -- NULL = unlimited; decremented per booking
        group_id           UUID       REFERENCES product(id),
            -- NULL = standalone; else this row is an option of the base article
            -- group_id points to. Options share their base's stock/points/
            -- requires_pager — see sales.py _resolve_base_products()/_effective().
        updated_at         TIMESTAMPTZ   DEFAULT now(),       -- bumped on any change; drives /changed sync
        created_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
    )""",
    # EVENT_CATEGORY / EVENT_PRODUCT — which of the tenant's categories and
    # articles are switched on in an event. event_product holds base
    # articles only; an option follows its base (COALESCE(p.group_id, p.id)).
    """
    CREATE TABLE event_category (
        event_id    UUID NOT NULL REFERENCES event(id),
        category_id UUID NOT NULL REFERENCES category(id),
        PRIMARY KEY (event_id, category_id)
    )""",
    """
    CREATE TABLE event_product (
        event_id   UUID NOT NULL REFERENCES event(id),
        product_id UUID NOT NULL REFERENCES product(id),
        PRIMARY KEY (event_id, product_id)
    )""",
    # USER CATEGORY ACCESS — per-category booking and article permissions,
    # valid in every event the category is switched on in. Separate from
    # permission_node because categories are dynamic data. Users with any
    # 'categories.*' permission are managers and bypass these rows.
    f"""
    CREATE TABLE user_category_access (
        id                     {ID},
        user_id                UUID     NOT NULL REFERENCES app_user(id),
        category_id            UUID     NOT NULL REFERENCES category(id),
        can_book               SMALLINT    NOT NULL DEFAULT 0,
        can_storno_5min        SMALLINT    NOT NULL DEFAULT 0,
        can_storno_unlimited   SMALLINT    NOT NULL DEFAULT 0,
        can_create_article     SMALLINT    NOT NULL DEFAULT 0,
        can_edit_article       SMALLINT    NOT NULL DEFAULT 0,
        can_deactivate_article SMALLINT    NOT NULL DEFAULT 0,
        can_delete_article     SMALLINT    NOT NULL DEFAULT 0,
        granted_by             UUID     REFERENCES app_user(id),
        granted_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE (user_id, category_id)
    )""",
    # CUSTOMER — guests with NFC chip, tenant-wide (balance survives fest
    # switches). Balance is ALWAYS server-side — the chip stores only the UID.
    # is_available = 1: chip is free (never issued or paid out).
    f"""
    CREATE TABLE customer (
        id            {ID},
        tenant_id     UUID       NOT NULL REFERENCES tenant(id),
        nfc_uid       TEXT          NOT NULL,
        display_name  TEXT,                     -- future: writable to tag
        balance       NUMERIC(10,2) NOT NULL DEFAULT 0,
        customer_name TEXT,                     -- optional name set by the customer at the kiosk
        is_available  SMALLINT      NOT NULL DEFAULT 1,
        deposit_paid  NUMERIC(10,2) NOT NULL DEFAULT 0,  -- Pfand actually taken; refunded exactly at payout
        created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
        UNIQUE (tenant_id, nfc_uid)
    )""",
    # LEADERBOARD — one opt-in per customer and event; points are the sum
    # of sale.points of the event.
    """
    CREATE TABLE leaderboard_entry (
        event_id    UUID  NOT NULL REFERENCES event(id),
        customer_id UUID  NOT NULL REFERENCES customer(id),
        opt_in      SMALLINT NOT NULL DEFAULT 0,
        PRIMARY KEY (event_id, customer_id)
    )""",
    # SALE — append-only; cancel sets cancelled = 1, never deletes.
    # price_at_sale: snapshot, price changes must not alter history.
    f"""
    CREATE TABLE sale (
        id            {ID},
        event_id      UUID       NOT NULL REFERENCES event(id),
        customer_id   UUID       NOT NULL REFERENCES customer(id),
        product_id    UUID       NOT NULL REFERENCES product(id),
        price_at_sale NUMERIC(10,2) NOT NULL,
        points        INTEGER       NOT NULL DEFAULT 0,  -- leaderboard points of this sale (0 at Intern)
        booked_by     UUID       NOT NULL REFERENCES app_user(id),
        booked_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),  -- used for the 5-min cancel check
        cancelled     SMALLINT      NOT NULL DEFAULT 0,
        cancelled_by  UUID       REFERENCES app_user(id),
        cancelled_at  TIMESTAMPTZ
    )""",
    # TOPUP — balance top-ups; payouts are a negative amount row.
    # payment_method: 'cash' (others are cloud placeholders)
    f"""
    CREATE TABLE topup (
        id             {ID},
        event_id       UUID       NOT NULL REFERENCES event(id),
        customer_id    UUID       NOT NULL REFERENCES customer(id),
        amount         NUMERIC(10,2) NOT NULL,
        payment_method TEXT          NOT NULL DEFAULT 'cash',
        booked_by      UUID       NOT NULL REFERENCES app_user(id),
        booked_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
        cancelled      SMALLINT      NOT NULL DEFAULT 0,
        cancelled_by   UUID       REFERENCES app_user(id),
        cancelled_at   TIMESTAMPTZ
    )""",
    # REFRESH TOKEN — token_hash: SHA-256 (never plaintext); revoked = 1 on logout
    f"""
    CREATE TABLE refresh_token (
        id          {ID},
        user_id     UUID     NOT NULL REFERENCES app_user(id),
        token_hash  TEXT        NOT NULL UNIQUE,
        device_info TEXT,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        expires_at  TIMESTAMPTZ NOT NULL,
        revoked     SMALLINT    NOT NULL DEFAULT 0
    )""",
    # USER PREFERENCE STORE — per-user key/value store.
    # key: e.g. 'layout.cat_3', 'product.color.42'; profile: 'P' | 'L' | '*';
    # value: JSON
    """
    CREATE TABLE user_preference_store (
        user_id UUID NOT NULL REFERENCES app_user(id),
        key     TEXT    NOT NULL,
        profile TEXT    NOT NULL DEFAULT '*',
        value   TEXT    NOT NULL,
        PRIMARY KEY (user_id, key, profile)
    )""",
    # STATS PERIOD — Tagesabschluss closes the current period and opens a
    # new one; closed_at NULL = current period.
    f"""
    CREATE TABLE stats_period (
        id         {ID},
        event_id   UUID     NOT NULL REFERENCES event(id),
        label      TEXT        NOT NULL,
        started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        closed_at  TIMESTAMPTZ,
        created_by UUID     REFERENCES app_user(id)
    )""",
    # HELP (Notfall): one request per call, one response per responder
    f"""
    CREATE TABLE help_request (
        id           {ID},
        event_id     UUID     NOT NULL REFERENCES event(id),
        requester_id UUID     NOT NULL REFERENCES app_user(id),
        status       TEXT        NOT NULL DEFAULT 'active',  -- active | resolved
        created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
    )""",
    f"""
    CREATE TABLE help_response (
        id           {ID},
        request_id   UUID     NOT NULL REFERENCES help_request(id),
        responder_id UUID     NOT NULL REFERENCES app_user(id),
        response     TEXT        NOT NULL,  -- 'on_way' | '5min' | 'cannot'
        created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE (request_id, responder_id)
    )""",
    # PRINT JOB QUEUE — one row per bon slip, printed FIFO by the worker.
    # Snapshots keep the bon showing the data from the moment of purchase.
    f"""
    CREATE TABLE print_job (
        id           {ID},
        event_id     UUID       NOT NULL REFERENCES event(id),
        sale_id      UUID       REFERENCES sale(id),
        username     TEXT          NOT NULL,
        event_name   TEXT          NOT NULL,
        product_name TEXT          NOT NULL,
        price        NUMERIC(10,2) NOT NULL,
        status       TEXT          NOT NULL DEFAULT 'pending',  -- pending|printing|done|error
        error_msg    TEXT,
        created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
        processed_at TIMESTAMPTZ
    )""",
    # PAGER ORDER — add-on. One row per booking with a requires_pager
    # article, scoped to the cashier (created_by). sale_ids: JSON list of
    # sale.id. Ending a fest force-closes open rows.
    f"""
    CREATE TABLE pager_order (
        id           {ID},
        event_id     UUID     NOT NULL REFERENCES event(id),
        created_by   UUID     NOT NULL REFERENCES app_user(id),
        item_summary TEXT        NOT NULL,             -- e.g. "2× Pizza Salami, Steak"
        pager_number INTEGER     NOT NULL,
        sale_ids     TEXT,
        status       TEXT        NOT NULL DEFAULT 'open',  -- open|done
        created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
        done_at      TIMESTAMPTZ
    )""",
    # DEVICE LOG LEVEL — one row per client device (+ '__server__').
    # forced_level NULL = no remote override. last_seen is in memory only
    # (device_registry.py).
    """
    CREATE TABLE device_log_level (
        device_id    TEXT        PRIMARY KEY,
        label        TEXT,
        platform     TEXT,
        forced_level TEXT,
        updated_by   UUID     REFERENCES app_user(id),
        updated_at   TIMESTAMPTZ
    )""",
    "CREATE INDEX idx_print_job_status       ON print_job(status, created_at)",
    "CREATE INDEX idx_pager_order_operator   ON pager_order(created_by, event_id, status)",
    "CREATE INDEX idx_sale_customer          ON sale(customer_id)",
    "CREATE INDEX idx_sale_event             ON sale(event_id)",
    "CREATE INDEX idx_sale_booked_at         ON sale(booked_at)",
    "CREATE INDEX idx_topup_customer         ON topup(customer_id)",
    "CREATE INDEX idx_customer_nfc           ON customer(nfc_uid)",
    "CREATE INDEX idx_product_category       ON product(category_id)",
    "CREATE INDEX idx_category_tenant        ON category(tenant_id)",
    "CREATE INDEX idx_event_product_product  ON event_product(product_id)",
    "CREATE UNIQUE INDEX one_active_event_per_tenant ON event(tenant_id) WHERE active = 1",
]


# Tables that get tenant_id from a parent row: (table, parent table, parent key column)
TENANT_FROM_PARENT = [
    ("product", "category", "category_id"),
    ("role_template_permission", "role_template", "role_template_id"),
    ("user_permission", "app_user", "user_id"),
    ("user_category_access", "app_user", "user_id"),
    ("refresh_token", "app_user", "user_id"),
    ("user_preference_store", "app_user", "user_id"),
    ("event_category", "event", "event_id"),
    ("event_product", "event", "event_id"),
    ("leaderboard_entry", "event", "event_id"),
    ("sale", "event", "event_id"),
    ("topup", "event", "event_id"),
    ("stats_period", "event", "event_id"),
    ("help_request", "event", "event_id"),
    ("print_job", "event", "event_id"),
    ("pager_order", "event", "event_id"),
    ("help_response", "help_request", "request_id"),
]
TENANT_DIRECT = ["event", "app_user", "role_template", "category", "customer"]

TRIGGER_SQL = [
    # No format()/%: SQLAlchemy would treat % as a parameter marker.
    """
    CREATE FUNCTION fill_tenant_id() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
        IF NEW.tenant_id IS NULL THEN
            EXECUTE 'SELECT tenant_id FROM ' || quote_ident(TG_ARGV[0]) || ' WHERE id = $1'
                INTO NEW.tenant_id USING (to_jsonb(NEW) ->> TG_ARGV[1])::uuid;
        END IF;
        RETURN NEW;
    END $$""",
    """
    CREATE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
        NEW.updated_at := now();
        RETURN NEW;
    END $$""",
]


def _tenant_statements() -> list[str]:
    out = []
    for table, parent, column in TENANT_FROM_PARENT:
        out.append(f"ALTER TABLE {table} ADD COLUMN tenant_id UUID NOT NULL REFERENCES tenant(id)")
        out.append(
            f"CREATE TRIGGER {table}_tenant BEFORE INSERT ON {table} "
            f"FOR EACH ROW EXECUTE FUNCTION fill_tenant_id('{parent}', '{column}')"
        )
    tenant_tables = TENANT_DIRECT + [t for t, _, _ in TENANT_FROM_PARENT]
    for table in ["tenant"] + tenant_tables:
        if table != "product":  # product already has updated_at (drives the catalog sync)
            out.append(f"ALTER TABLE {table} ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT now()")
        out.append(
            f"CREATE TRIGGER {table}_touch BEFORE UPDATE ON {table} "
            f"FOR EACH ROW EXECUTE FUNCTION touch_updated_at()"
        )
    for table in tenant_tables:
        if table not in TENANT_DIRECT and table != "event":
            out.append(f"CREATE INDEX idx_{table}_tenant ON {table}(tenant_id)")
    return out


def upgrade() -> None:
    for statement in STATEMENTS + TRIGGER_SQL + _tenant_statements():
        op.execute(statement)


def downgrade() -> None:
    raise NotImplementedError("Baseline: drop the database instead.")
