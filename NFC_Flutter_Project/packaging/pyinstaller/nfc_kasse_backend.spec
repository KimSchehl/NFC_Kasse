# PyInstaller spec for the NFC-Kasse backend service entrypoint
# (backend/service_main.py). Build with:
#   python packaging/pyinstaller/stage_updates_seed.py
#   python -m PyInstaller packaging/pyinstaller/nfc_kasse_backend.spec --distpath packaging/pyinstaller/dist --workpath packaging/pyinstaller/build/work
#
# Onedir, not onefile — see packaging plan Phase 2.1: avoids re-extracting the
# whole bundle (uvicorn/cryptography/pydantic-core/escpos + webapp/updates
# data) on every service (re)start, and onefile's self-extract-to-temp
# pattern is a well-known AV/SmartScreen false-positive trigger.

from pathlib import Path

REPO_ROOT = Path(SPECPATH).parent.parent  # packaging/pyinstaller -> repo root
BACKEND = REPO_ROOT / "backend"
ICON = REPO_ROOT / "packaging" / "innosetup" / "assets" / "nfc_kasse.ico"

a = Analysis(
    [str(BACKEND / "service_main.py")],
    pathex=[str(BACKEND)],
    # ^ load-bearing: every module in backend/ uses bare imports
    # (`import database`, `from routers import auth, ...`), exactly like
    # pytest.ini's `pythonpath = .` already relies on. Without this,
    # Analysis fails immediately with ModuleNotFoundError: No module named
    # 'database' — not a subtle runtime bug, a build-time one.
    binaries=[],
    datas=[
        (str(BACKEND / "bon_template.yaml"), "."),
        # Reference/documentation only — not read by any code, just bundled
        # next to the program for discoverability. The live file (bon.yaml)
        # lives in NFC_KASSE_DATA_DIR (ProgramData), seeded from bon.yaml.default.
        (str(BACKEND / "bon.yaml.default"), "."),
        # -> Path(__file__).parent from service_main.py's _ensure_bon_yaml()
        (str(BACKEND / "config.env.template"), "."),
        # -> Path(__file__).parent from service_main.py's _ensure_config()
        (str(BACKEND / "webapp"), "webapp"),
        # -> Path(__file__).parent from main.py's webapp mount
        (str(REPO_ROOT / "packaging" / "pyinstaller" / "build" / "updates_seed"), "updates"),
        # -> Path(__file__).parent.parent from routers/update.py + download.py
        # Populated by stage_updates_seed.py — NOT backend/updates/ directly
        # (that's 1+ GB of historical release APKs; only the newest matters
        # at runtime, see that script's own docstring).
    ],
    hiddenimports=[
        # uvicorn[standard]'s runtime-selected implementations — invisible to
        # PyInstaller's static import-graph walk.
        "uvicorn.loops.auto",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.http.h11_impl",
        "uvicorn.protocols.http.httptools_impl",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.protocols.websockets.websockets_impl",
        "uvicorn.protocols.websockets.wsproto_impl",
        "uvicorn.lifespan.on",
        "uvicorn.logging",
        "h11",
        "httptools",
        "websockets",
        "wsproto",
        # python-escpos is imported lazily inside printer.py's _get_printer()
        # specifically so the server starts without it installed — invisible
        # to Analysis for the same reason.
        "escpos",
        "escpos.printer",
        "escpos.escpos",
        "escpos.capabilities",
        # Starlette's Form()-parsing code path (used by the login endpoint)
        # imports this lazily.
        "multipart",
    ],
    excludes=[
        # uvloop is Unix-only (uvicorn[standard]'s own extras marker is
        # sys_platform != 'win32') — pip never installs it on Windows, so no
        # hidden-import here could ever be satisfied.
        "uvicorn.loops.uvloop",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="NfcKasseBackend",
    console=True,
    # ^ not cosmetic: a Windows service has no attached console regardless
    # of this flag, but console=True keeps sys.stdout/stderr valid stream
    # objects instead of None — see packaging plan Phase 2.4. uvicorn's own
    # StreamHandler setup would crash on the very first log call otherwise.
    icon=str(ICON) if ICON.exists() else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    name="NfcKasseBackend",
    # -> dist/NfcKasseBackend/NfcKasseBackend.exe (+ its data/binaries) —
    # this whole folder is what Phase 4's Inno Setup installer copies to
    # {app}.
)
