"""
Customer-facing display — shows the current cart state for each cashier station.

Architecture:
  POST /api/display/update          — cashier app pushes cart state (requires auth)
  GET  /api/display/stations        — list of active stations (no auth, browser polling)
  GET  /api/display/stream/{user}   — SSE stream per station (no auth, browser)
  GET  /display                     — station selection page (HTML)
  GET  /display/{username}          — customer display page  (HTML)

State is in-memory only (dict keyed by lowercase username).
A server restart clears all display states — stations reappear after the first
cart change on the cashier tablet.
"""

import asyncio
import html as _html
import json
import time

from fastapi import Depends
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.routing import APIRouter

from dependencies import get_active_event, get_current_user
from schemas import DisplayUpdateRequest

# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------

# username (lowercase) → {seq, username, label, items, chip_uid,
#                          current_balance, balance_after, updated_at}
_states: dict[str, dict] = {}
_seq: int = 0


def _push(username: str, label: str, payload: dict) -> None:
    global _seq
    _seq += 1
    _states[username.lower()] = {
        "seq": _seq,
        "username": username.lower(),
        "label": label,
        **payload,
        "updated_at": time.time(),
    }


# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------

router = APIRouter(tags=["display"])                    # HTML pages — no /api prefix
api_router = APIRouter(prefix="/api/display", tags=["display"])


# ---------------------------------------------------------------------------
# API — cashier push
# ---------------------------------------------------------------------------

@api_router.post("/update")
def update_display(
    body: DisplayUpdateRequest,
    user: dict = Depends(get_current_user),
    event: dict = Depends(get_active_event),
):
    """Cashier app pushes current cart state. Any authenticated user may call this."""
    label = user.get("display_name") or user["username"]
    _push(user["username"], label, {
        "items": [
            {"name": i.name, "price": i.price, "quantity": i.quantity}
            for i in body.items
        ],
        "chip_uid": body.chip_uid,
        "current_balance": body.current_balance,
        "balance_after": body.balance_after,
    })
    return {"ok": True}


# ---------------------------------------------------------------------------
# API — station list (browser polls this every 5 s)
# ---------------------------------------------------------------------------

@api_router.get("/stations")
def list_stations():
    """Returns stations that pushed an update in the last 90 seconds."""
    cutoff = time.time() - 90
    return [
        {"username": v["username"], "label": v["label"]}
        for v in _states.values()
        if v["updated_at"] > cutoff
    ]


# ---------------------------------------------------------------------------
# API — SSE stream per station
# ---------------------------------------------------------------------------

@api_router.get("/stream/{username}")
async def stream_display(username: str):
    """Server-Sent Events stream for a specific station. No auth required."""
    key = username.lower()

    async def generate():
        last_seq = -1
        while True:
            state = _states.get(key)
            cur_seq = state["seq"] if state else -1
            if cur_seq != last_seq:
                last_seq = cur_seq
                data = json.dumps(state) if state else '{"empty":true}'
                yield f"data: {data}\n\n"
            await asyncio.sleep(0.3)

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------------------------------------------------------------------------
# HTML — station selection page  (/display)
# ---------------------------------------------------------------------------

_INDEX_HTML = """\
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kundenterminal – Standsauswahl</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d0d0d;color:#f0f0f0;font-family:system-ui,sans-serif;min-height:100vh}
header{background:#1a1a1a;padding:20px 24px;border-bottom:1px solid #2a2a2a;display:flex;align-items:baseline;gap:12px}
h1{font-size:1.4rem;font-weight:600}
.sub{color:#555;font-size:1rem;font-weight:300}
#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:16px;padding:28px}
.card{background:#1a1a1a;border:1px solid #2e2e2e;border-radius:14px;padding:28px 16px;text-align:center;
  cursor:pointer;text-decoration:none;color:inherit;display:block;transition:background .15s,border-color .15s}
.card:hover{background:#222;border-color:#555}
.card-name{font-size:1.35rem;font-weight:600;margin-bottom:10px}
.card-dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:#4caf50;margin-right:5px}
.card-status{font-size:.85rem;color:#4caf50}
#empty{padding:60px 24px;text-align:center;color:#444;font-size:1.1rem;line-height:1.8;display:none}
</style>
</head>
<body>
<header><h1>Kundenterminal</h1><span class="sub">Standsauswahl</span></header>
<div id="grid"></div>
<div id="empty">Keine aktiven Stationen gefunden.<br>Bitte am Kassiergerät anmelden und Artikel auswählen.</div>
<script>
async function refresh(){
  try{
    const r=await fetch('/api/display/stations');
    const list=await r.json();
    const g=document.getElementById('grid');
    const e=document.getElementById('empty');
    if(!list.length){g.innerHTML='';e.style.display='block';return;}
    e.style.display='none';
    g.innerHTML=list.map(s=>
      `<a class="card" href="/display/${encodeURIComponent(s.username)}">
        <div class="card-name">${s.label}</div>
        <div class="card-status"><span class="card-dot"></span>aktiv</div>
      </a>`).join('');
  }catch(_){}
}
refresh();
setInterval(refresh,5000);
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# HTML — customer display page  (/display/{username})
# ---------------------------------------------------------------------------

_STATION_HTML = """\
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Kundenterminal</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{background:#0d0d0d;color:#f0f0f0;font-family:system-ui,sans-serif;
  display:flex;flex-direction:column;
  height:100vh;height:100dvh}
header{background:#161616;padding:10px 20px;display:flex;justify-content:space-between;
  align-items:center;border-bottom:1px solid #232323;flex-shrink:0}
.station{font-size:1rem;font-weight:600;color:#888}
.brand{font-size:.85rem;color:#3a3a3a}
#main{flex:1;display:flex;flex-direction:column;overflow:hidden}

/* Waiting state */
#waiting{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px}
.w-icon{font-size:3rem;opacity:.15}
.w-text{font-size:1.8rem;font-weight:300;color:#444;letter-spacing:.02em}

/* Cart state */
#cart{flex:1;display:none;flex-direction:column;overflow:hidden}
#items{flex:1;overflow-y:auto;padding:4px 0}
.item{display:flex;align-items:center;padding:16px 20px;border-bottom:1px solid #1b1b1b}
.item-name{flex:1;font-size:1.55rem;font-weight:500;line-height:1.2}
.item-price{font-size:1.55rem;font-weight:600;color:#ddd;white-space:nowrap;padding-left:12px}
.item-price.refund{color:#4caf50}

/* Totals */
#totals{flex-shrink:0;border-top:2px solid #222;background:#111;padding:14px 20px 10px}
#totals.no-balance{padding-bottom:calc(10px + env(safe-area-inset-bottom,0px))}
.row{display:flex;justify-content:space-between;align-items:baseline;padding:3px 0}
.lbl{color:#888;font-size:1.05rem}
.val{font-weight:600;font-size:1.05rem}
.grand .lbl,.grand .val{font-size:1.75rem;color:#fff;font-weight:700}

/* Balance */
#balance{flex-shrink:0;border-top:1px solid #1e1e1e;background:#0a0a0a;
  padding:10px 20px calc(14px + env(safe-area-inset-bottom,0px))}
.pos{color:#4caf50}
.neg{color:#f44336}

/* Reconnect banner */
#offline{display:none;position:fixed;bottom:0;left:0;right:0;background:#b71c1c;
  color:#fff;text-align:center;padding:8px;font-size:.9rem}
</style>
</head>
<body>
<header>
  <span class="station" id="station-label">__USERNAME__</span>
  <span class="brand">NFC-Kasse</span>
</header>
<div id="main">
  <div id="waiting">
    <div class="w-icon">🛒</div>
    <div class="w-text">Bitte warten …</div>
  </div>
  <div id="cart">
    <div id="items"></div>
    <div id="totals">
      <div class="row grand">
        <span class="lbl">Gesamt:</span>
        <span class="val" id="total"></span>
      </div>
    </div>
    <div id="balance" style="display:none">
      <div class="row">
        <span class="lbl">Aktuelles Guthaben:</span>
        <span class="val" id="bal-cur"></span>
      </div>
      <div class="row">
        <span class="lbl">Nach Buchung:</span>
        <span class="val" id="bal-after"></span>
      </div>
    </div>
  </div>
</div>
<div id="offline">Verbindung unterbrochen – Wiederverbindung …</div>
<script>
const USERNAME='__USERNAME__';

function fmt(v){
  return (Math.round(v*100)/100).toFixed(2).replace('.',',')+' €';
}

function render(data){
  const hasItems=data.items&&data.items.length>0;
  const hasChip=data.chip_uid!=null;

  if(data.empty||(!hasItems&&!hasChip)){
    document.getElementById('waiting').style.display='flex';
    document.getElementById('cart').style.display='none';
    return;
  }
  document.getElementById('waiting').style.display='none';
  document.getElementById('cart').style.display='flex';

  // Update station label from server data
  if(data.label) document.getElementById('station-label').textContent=data.label;

  // Items
  const itemsEl=document.getElementById('items');
  let total=0;
  itemsEl.innerHTML=(data.items||[]).map(i=>{
    const sub=i.price*i.quantity;
    total+=sub;
    const qty=i.quantity>1?`${i.quantity}× `:'';
    const cls=i.price<0?'item-price refund':'item-price';
    return `<div class="item"><span class="item-name">${qty}${i.name}</span>`+
           `<span class="${cls}">${fmt(sub)}</span></div>`;
  }).join('');
  document.getElementById('total').textContent=fmt(total);

  // Balance
  const balEl=document.getElementById('balance');
  const totalsEl=document.getElementById('totals');
  if(hasChip&&data.current_balance!=null){
    balEl.style.display='block';
    totalsEl.classList.remove('no-balance');
    document.getElementById('bal-cur').textContent=fmt(data.current_balance);
    const after=data.balance_after??0;
    const el=document.getElementById('bal-after');
    el.textContent=fmt(after);
    el.className='val '+(after>=0?'pos':'neg');
  } else {
    balEl.style.display='none';
    totalsEl.classList.add('no-balance');
  }
}

let es;
function connect(){
  document.getElementById('offline').style.display='none';
  es=new EventSource('/api/display/stream/'+encodeURIComponent(USERNAME));
  es.onmessage=e=>{try{render(JSON.parse(e.data));}catch(_){}};
  es.onerror=()=>{
    es.close();
    document.getElementById('offline').style.display='block';
    setTimeout(connect,3000);
  };
}
connect();
</script>
</body>
</html>
"""


@router.get("/display", response_class=HTMLResponse)
def display_index():
    return HTMLResponse(content=_INDEX_HTML)


@router.get("/display/{username}", response_class=HTMLResponse)
def display_station(username: str):
    safe = _html.escape(username.lower())
    return HTMLResponse(content=_STATION_HTML.replace("__USERNAME__", safe))
