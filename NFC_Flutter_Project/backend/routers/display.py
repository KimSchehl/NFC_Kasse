"""
Customer-facing display — shows the current cart state for each cashier station.

Architecture:
  POST /api/display/update          — cashier app pushes cart state (requires auth)
  notify_booked()                   — sales.py reports a finished booking/payout,
                                      the page then shows the confirmation screen
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
#                          current_balance, balance_after, confirmation,
#                          updated_at}
_states: dict[str, dict] = {}
_seq: int = 0

# How long a booking confirmation survives the app's own follow-up pushes
# (it clears chip and cart right after the booking). The page itself shows it
# for CONFIRM_SHOW_MS (see _STATION_HTML) or until the next chip is scanned.
CONFIRM_HOLD_SECONDS = 8


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


def _recent_confirmation(username: str) -> dict | None:
    prev = _states.get(username.lower())
    conf = prev.get("confirmation") if prev else None
    if conf and time.time() - conf["at"] < CONFIRM_HOLD_SECONDS:
        return conf
    return None


def notify_booked(user: dict, new_balance: float, payout_amount: float | None = None) -> None:
    """Called by sales.py after a committed booking: the station's display shows
    "Buchung bestätigt" with the remaining balance (or "Auszahlung bestätigt"
    with the paid-out amount). Only the server knows the booking really went
    through and the exact new balance, so this does not come from the app."""
    label = user.get("display_name") or user["username"]
    _push(user["username"], label, {
        "items": [],
        "chip_uid": None,
        "current_balance": None,
        "balance_after": None,
        "confirmation": {
            "id": _seq + 1,  # = the seq of this very push
            "kind": "payout" if payout_amount is not None else "booking",
            "balance": new_balance,
            "amount": payout_amount,
            "at": time.time(),
        },
    })


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
        "confirmation": _recent_confirmation(user["username"]),
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
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
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
#main{flex:1;display:flex;flex-direction:column;overflow:hidden;position:relative}

/* Waiting state: chip being placed on the reader */
#waiting{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;
  gap:18px;padding:20px;text-align:center}
.tap{width:min(52vmin,300px);height:auto;overflow:visible}
.w-text{font-size:clamp(1.8rem,5.5vmin,3rem);font-weight:600;color:#f0f0f0;letter-spacing:.01em}
.w-sub{font-size:clamp(1rem,2.8vmin,1.4rem);color:#777}

.chip,.chip-shadow{transform-box:fill-box;transform-origin:center}
.chip{animation:chip-move 3.2s cubic-bezier(.3,.7,.3,1) infinite}
.chip-shadow{animation:chip-shadow 3.2s cubic-bezier(.3,.7,.3,1) infinite}
.wave{fill:none;stroke:#4caf50;stroke-width:3;opacity:0;
  transform-box:fill-box;transform-origin:center;animation:wave 3.2s ease-out infinite}
.wave.w2{animation-delay:.25s}
.led{animation:led 3.2s linear infinite}
@keyframes chip-move{
  0%  {transform:translate(70px,-90px) scale(1.45);opacity:0}
  12% {opacity:1}
  42% {transform:translate(0,0) scale(1);opacity:1}
  80% {transform:translate(0,0) scale(1);opacity:1}
  100%{transform:translate(0,0) scale(1);opacity:0}}
@keyframes chip-shadow{
  0%  {transform:translate(40px,-30px) scale(1.5);opacity:0}
  42% {transform:translate(0,0) scale(1);opacity:.55}
  80% {opacity:.55}
  100%{opacity:0}}
@keyframes wave{
  0%,42%{transform:scale(1);opacity:0}
  46%   {opacity:.9}
  75%   {transform:scale(1.9);opacity:0}
  100%  {opacity:0}}
@keyframes led{0%,42%{fill:#3a3f46}44%,80%{fill:#4caf50}84%,100%{fill:#3a3f46}}

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

/* Cart without chip yet: prompt at the bottom */
#tap-hint{flex-shrink:0;display:none;align-items:center;justify-content:center;gap:12px;
  background:#12261a;border-top:1px solid #1f4d2c;color:#c8f0d2;font-size:1.4rem;font-weight:600;
  padding:16px 20px calc(16px + env(safe-area-inset-bottom,0px))}
.hint-dot{width:12px;height:12px;border-radius:50%;background:#4caf50;animation:pulse 1.4s ease-in-out infinite}
@keyframes pulse{0%,100%{opacity:.3;transform:scale(.8)}50%{opacity:1;transform:scale(1.15)}}

/* Booking confirmed */
#confirm{position:absolute;inset:0;background:#0d0d0d;display:none;flex-direction:column;
  align-items:center;justify-content:center;gap:10px;padding:20px;text-align:center}
#confirm.show{display:flex}
.check{width:min(38vmin,220px);height:auto;margin-bottom:14px}
.check circle{fill:#2e9d4f;transform-box:fill-box;transform-origin:center}
.check path{fill:none;stroke:#fff;stroke-width:9;stroke-linecap:round;stroke-linejoin:round;
  stroke-dasharray:80;stroke-dashoffset:80}
#confirm.show .check circle{animation:pop .45s cubic-bezier(.2,1.6,.4,1) both}
#confirm.show .check path{animation:draw .35s ease-out .3s forwards}
.c-title{font-size:clamp(1.8rem,6vmin,3.2rem);font-weight:700;color:#fff;
  opacity:0}
.c-label{font-size:clamp(1.6rem,5.5vmin,2.8rem);font-weight:600;color:#bbb;margin-top:26px;opacity:0}
.c-amount{font-size:clamp(3.5rem,15vmin,8rem);font-weight:800;line-height:1.05;
  font-variant-numeric:tabular-nums;opacity:0}
#confirm.show .c-title{animation:rise .35s ease-out .25s forwards}
#confirm.show .c-label{animation:rise .35s ease-out .4s forwards}
#confirm.show .c-amount{animation:rise .35s ease-out .45s forwards}
@keyframes pop{0%{transform:scale(0)}100%{transform:scale(1)}}
@keyframes draw{to{stroke-dashoffset:0}}
@keyframes rise{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}

@media (prefers-reduced-motion:reduce){
  .chip,.chip-shadow,.wave,.led,.hint-dot{animation:none}
  .wave{opacity:0}
  #confirm.show .check circle,#confirm.show .c-title,#confirm.show .c-label,#confirm.show .c-amount{animation:none;opacity:1}
  #confirm.show .check path{animation:none;stroke-dashoffset:0}
}

/* Touch lock: the display hangs in front of guests, so a transparent layer
   swallows every touch. Holding the top-right corner (top-left is Headwind
   MDM's kiosk exit) for UNLOCK_HOLD_MS frees
   touch for UNLOCK_MS; tapping the banner locks again at once. */
body{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent}
#lock{position:fixed;inset:0;z-index:50;touch-action:none}
#lock.off{display:none}
#unlocked{display:none;position:fixed;top:0;left:0;right:0;z-index:60;background:#e65100;
  color:#fff;padding:10px 12px;font-size:1rem;font-weight:600;align-items:center;gap:12px}
#unlocked.show{display:flex}
#unlocked .msg{flex:1}
#unlocked a{color:#e65100;background:#fff;border-radius:8px;padding:8px 14px;text-decoration:none;white-space:nowrap}

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
    <svg class="tap" viewBox="0 0 240 240" aria-hidden="true">
      <defs>
        <linearGradient id="chipg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#4a92ff"/>
          <stop offset="1" stop-color="#1f5fc4"/>
        </linearGradient>
      </defs>
      <!-- reader, seen from above -->
      <rect x="30" y="30" width="180" height="180" rx="34" fill="#1b1e23" stroke="#2c3138" stroke-width="2"/>
      <rect x="44" y="44" width="152" height="152" rx="24" fill="#16191d"/>
      <circle class="led" cx="186" cy="54" r="5" fill="#3a3f46"/>
      <g fill="none" stroke="#3a414b" stroke-width="6" stroke-linecap="round">
        <path d="M108 100 a28 28 0 0 1 0 40"/>
        <path d="M122 88 a46 46 0 0 1 0 64"/>
        <path d="M136 76 a64 64 0 0 1 0 88"/>
      </g>
      <circle class="wave" cx="120" cy="120" r="46"/>
      <circle class="wave w2" cx="120" cy="120" r="46"/>
      <!-- chip (key fob) -->
      <ellipse class="chip-shadow" cx="124" cy="128" rx="44" ry="44" fill="#000" fill-opacity=".6"/>
      <g class="chip">
        <circle cx="120" cy="120" r="44" fill="url(#chipg)"/>
        <circle cx="120" cy="120" r="34" fill="none" stroke="#ffffff" stroke-opacity=".25" stroke-width="2"/>
        <circle cx="120" cy="86" r="5" fill="#16191d"/>
        <g fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round">
          <path d="M112 110 a14 14 0 0 1 0 20"/>
          <path d="M120 103 a24 24 0 0 1 0 34"/>
          <path d="M128 96 a34 34 0 0 1 0 48"/>
        </g>
      </g>
    </svg>
    <div class="w-text">Chip auf Lesegerät legen</div>
    <div class="w-sub">oder das Armband an das Lesegerät halten</div>
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
    <div id="tap-hint"><span class="hint-dot"></span>Chip auf Lesegerät legen</div>
  </div>
  <div id="confirm" role="status" aria-live="polite">
    <svg class="check" viewBox="0 0 100 100" aria-hidden="true">
      <circle cx="50" cy="50" r="48"/>
      <path d="M28 52 L44 67 L73 36"/>
    </svg>
    <div class="c-title" id="c-title">Buchung bestätigt</div>
    <div class="c-label" id="c-label">Restguthaben</div>
    <div class="c-amount" id="c-amount"></div>
  </div>
</div>
<div id="offline">Verbindung unterbrochen – Wiederverbindung …</div>
<div id="lock"></div>
<div id="unlocked"><span class="msg">Touch frei – sperrt in <span id="unlock-left"></span> s · Tippen sperrt sofort</span><a href="/display">Kasse wechseln</a></div>
<script>
const USERNAME='__USERNAME__';
// How long "Buchung bestätigt" stays up, unless the next chip is scanned first.
const CONFIRM_SHOW_MS=6000;

function fmt(v){
  return (Math.round(v*100)/100).toFixed(2).replace('.',',')+' €';
}

let seenConfirm=null;   // id of the last confirmation already handled
let confirmTimer=null;
let firstMessage=true;

function hideConfirm(){
  clearTimeout(confirmTimer);
  document.getElementById('confirm').classList.remove('show');
}

function showConfirm(c){
  const payout=c.kind==='payout';
  document.getElementById('c-title').textContent=payout?'Auszahlung bestätigt':'Buchung bestätigt';
  document.getElementById('c-label').textContent=payout?'Ausgezahlt':'Restguthaben';
  const v=payout?c.amount:c.balance;
  const el=document.getElementById('c-amount');
  el.textContent=fmt(v??0);
  el.className='c-amount '+(!payout&&v<0?'neg':'');
  const box=document.getElementById('confirm');
  box.classList.remove('show');
  void box.offsetWidth;  // restart the pop-in animation
  box.classList.add('show');
  clearTimeout(confirmTimer);
  confirmTimer=setTimeout(hideConfirm,CONFIRM_SHOW_MS);
}

function render(data){
  const hasItems=data.items&&data.items.length>0;
  const hasChip=data.chip_uid!=null;

  // A confirmation already on the server when the page opens is old news.
  const c=data.confirmation;
  if(c&&c.id!==seenConfirm){
    seenConfirm=c.id;
    if(!firstMessage) showConfirm(c);
  }
  firstMessage=false;
  // Next guest's chip scanned: get out of the way at once.
  if(hasChip) hideConfirm();

  if(data.label) document.getElementById('station-label').textContent=data.label;

  if(data.empty||(!hasItems&&!hasChip)){
    document.getElementById('waiting').style.display='flex';
    document.getElementById('cart').style.display='none';
    return;
  }
  document.getElementById('waiting').style.display='none';
  document.getElementById('cart').style.display='flex';

  // Items
  const itemsEl=document.getElementById('items');
  let total=0;
  itemsEl.innerHTML=(data.items||[]).map(i=>{
    const sub=i.price*i.quantity;
    total+=sub;
    const qty=i.quantity>1?`${i.quantity}× `:'';
    const cls=i.price<0?'item-price refund':'item-price';
    return `<div class="item"><span class="item-name">${qty}${i.name}</span>`+
           `<span class="${cls}">${fmt(sub)}</span></div>`;
  }).join('');
  document.getElementById('total').textContent=fmt(total);

  // Balance, or the prompt to put the chip on the reader
  const balEl=document.getElementById('balance');
  const totalsEl=document.getElementById('totals');
  const hintEl=document.getElementById('tap-hint');
  if(hasChip&&data.current_balance!=null){
    balEl.style.display='block';
    hintEl.style.display='none';
    totalsEl.classList.remove('no-balance');
    document.getElementById('bal-cur').textContent=fmt(data.current_balance);
    const after=data.balance_after??0;
    const el=document.getElementById('bal-after');
    el.textContent=fmt(after);
    el.className='val '+(after>=0?'pos':'neg');
  } else {
    balEl.style.display='none';
    hintEl.style.display=hasChip?'none':'flex';
    totalsEl.classList.toggle('no-balance',hasChip);
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

// --- Touch lock -----------------------------------------------------------
const UNLOCK_HOLD_MS=5000;   // hold the corner this long to unlock
const UNLOCK_CORNER_PX=90;   // size of the secret top-right corner
const UNLOCK_MS=30000;       // touch stays free this long

const lockEl=document.getElementById('lock');
const unlockedEl=document.getElementById('unlocked');
let holdTimer=null, relockTimer=null, tickTimer=null;

function goFullscreen(){
  const d=document.documentElement;
  if(document.fullscreenElement||!d.requestFullscreen) return;
  d.requestFullscreen({navigationUI:'hide'}).catch(()=>{});
}

function lockTouch(){
  clearTimeout(relockTimer);
  clearInterval(tickTimer);
  unlockedEl.classList.remove('show');
  lockEl.classList.remove('off');
}

function unlockTouch(){
  lockEl.classList.add('off');
  unlockedEl.classList.add('show');
  const until=Date.now()+UNLOCK_MS;
  const tick=()=>{
    document.getElementById('unlock-left').textContent=Math.max(0,Math.ceil((until-Date.now())/1000));
  };
  tick();
  tickTimer=setInterval(tick,1000);
  relockTimer=setTimeout(lockTouch,UNLOCK_MS);
}

function cancelHold(){ clearTimeout(holdTimer); holdTimer=null; }

lockEl.addEventListener('pointerdown',e=>{
  e.preventDefault();
  if(e.clientX>innerWidth-UNLOCK_CORNER_PX&&e.clientY<UNLOCK_CORNER_PX){
    cancelHold();
    holdTimer=setTimeout(()=>{holdTimer=null;unlockTouch();},UNLOCK_HOLD_MS);
  }
});
// Any touch is a user gesture: use it to (re-)enter fullscreen. For touch,
// browsers grant that on pointerup, not pointerdown.
lockEl.addEventListener('pointerup',()=>{cancelHold();goFullscreen();});
lockEl.addEventListener('pointercancel',cancelHold);
lockEl.addEventListener('pointermove',e=>{
  if(holdTimer&&(e.clientX<=innerWidth-UNLOCK_CORNER_PX||e.clientY>=UNLOCK_CORNER_PX)) cancelHold();
});
for(const t of ['touchstart','touchmove','touchend']){
  lockEl.addEventListener(t,e=>e.preventDefault(),{passive:false});
}
document.addEventListener('contextmenu',e=>{if(!lockEl.classList.contains('off')) e.preventDefault();});
unlockedEl.addEventListener('click',e=>{if(!e.target.closest('a')) lockTouch();});
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
