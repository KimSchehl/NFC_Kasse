"""Licence keys: the main licence (feature "kasse") and the add-ons."""
import io
import json
from datetime import date

import pytest

import admin_cli
import licensing
from tests.conftest import _sign_test_license, _test_private_key, _TEST_INSTALLATION_ID


def _sign(payload: dict) -> str:
    import base64

    b64 = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=").decode("ascii")
    raw = json.dumps(payload, separators=(",", ":")).encode()
    return f"{b64(raw)}.{b64(_test_private_key.sign(raw))}"


def test_statuses():
    ok = _sign({"v": 1, "installation_id": _TEST_INSTALLATION_ID, "feature": "kasse"})
    assert licensing.check("kasse", _TEST_INSTALLATION_ID, ok)["status"] == licensing.VALID
    assert licensing.check("kasse", _TEST_INSTALLATION_ID, "")["status"] == licensing.MISSING
    assert licensing.check("kasse", _TEST_INSTALLATION_ID, "kaputt")["status"] == licensing.INVALID
    assert licensing.check("kasse", "andere-id", ok)["status"] == licensing.WRONG_INSTALLATION
    assert licensing.check("pager", _TEST_INSTALLATION_ID, ok)["status"] == licensing.WRONG_FEATURE
    forged = ok[:-4] + ("AAAA" if not ok.endswith("AAAA") else "BBBB")
    assert licensing.check("kasse", _TEST_INSTALLATION_ID, forged)["status"] == licensing.INVALID


def test_expiry():
    key = _sign({"v": 1, "installation_id": _TEST_INSTALLATION_ID, "feature": "kasse", "valid_until": "2026-12-31"})
    assert licensing.check("kasse", _TEST_INSTALLATION_ID, key, today=date(2026, 12, 31))["status"] == licensing.VALID
    expired = licensing.check("kasse", _TEST_INSTALLATION_ID, key, today=date(2027, 1, 1))
    assert expired == {"status": licensing.EXPIRED, "valid_until": "2026-12-31"}


def test_license_check_command_reads_config_env_and_overrides(tmp_path, capsys):
    (tmp_path / "config.env").write_text(
        f"INSTALLATION_ID={_TEST_INSTALLATION_ID}\nPAGER_LICENSE_KEY={_sign_test_license('pager')}\n", encoding="utf-8"
    )
    code = admin_cli.main(["license-check", "--kasse", "falsch"], tmp_path, db_path=tmp_path / "fehlt.db")
    out = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert code == 0, out
    assert out["licenses"]["pager"]["status"] == "valid"
    assert out["licenses"]["kasse"]["status"] == "invalid"
    assert out["licenses"]["leaderboard"]["status"] == "missing"


def test_service_refuses_to_start_without_main_license(monkeypatch):
    import service_main

    monkeypatch.setenv("INSTALLATION_ID", _TEST_INSTALLATION_ID)
    monkeypatch.setenv("LICENSE_KEY", "")
    with pytest.raises(SystemExit) as exc:
        service_main._require_main_license()
    assert exc.value.code == 2
    monkeypatch.setenv("LICENSE_KEY", _sign({"v": 1, "installation_id": _TEST_INSTALLATION_ID, "feature": "kasse"}))
    service_main._require_main_license()  # no exit


def test_article_admin_stays_reachable_without_switched_on_categories(client, auth_headers):
    me = client.get("/api/auth/me", headers=auth_headers).json()
    assert me["categories"] == [] and me["can_manage_articles"] is True
