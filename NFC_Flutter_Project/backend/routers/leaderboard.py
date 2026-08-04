"""
Leaderboard — real-time best-drinkers list.

Architecture:
  GET /leaderboard              — HTML page (TV display, no auth)
  GET /api/leaderboard          — JSON top 10 (no auth)
  GET /api/leaderboard/stream   — SSE stream (no auth)

Points are calculated on-the-fly: SUM(product.points) per chip for all
non-cancelled sales where the chip has leaderboard_opt_in=1.

SSE only fires when the actual top-10 changes (by uid + score), so bookings
that only move the 11th place do not cause a client refresh.

Call check_and_notify() from any router that mutates sales or leaderboard_opt_in.
"""

import asyncio
import json

from fastapi import APIRouter
from fastapi.responses import HTMLResponse, StreamingResponse

from database import get_db

# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------

_seq: int = 0
_current_top10: list[dict] = []
_current_key: tuple = ()


def _fetch_top10() -> list[dict]:
    with get_db() as db:
        rows = db.execute("""
            SELECT
                c.nfc_uid,
                COALESCE(c.customer_name, 'Anonym') AS display_name,
                ls.points AS total_points
            FROM leaderboard_score ls
            JOIN customer c ON ls.customer_id = c.id
            WHERE ls.opt_in = 1
            ORDER BY ls.points DESC, ls.customer_id ASC
            LIMIT 10
        """).fetchall()
    return [
        {
            "rank": i + 1,
            "name": r["display_name"],
            "nfc_uid": r["nfc_uid"],
            "points": r["total_points"],
        }
        for i, r in enumerate(rows)
    ]


def _make_key(top10: list[dict]) -> tuple:
    return tuple((e["nfc_uid"], e["points"]) for e in top10)


def check_and_notify() -> None:
    """Called after any sale/cancel/opt-in mutation. Pushes SSE only if top 10 changed."""
    global _seq, _current_top10, _current_key
    try:
        new_top10 = _fetch_top10()
        new_key = _make_key(new_top10)
        if new_key != _current_key:
            _current_top10 = new_top10
            _current_key = new_key
            _seq += 1
    except Exception:
        pass


# Initialise on import so first SSE client gets real data immediately.
check_and_notify()


# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------

router = APIRouter(tags=["leaderboard"])
api_router = APIRouter(prefix="/api/leaderboard", tags=["leaderboard"])


@api_router.get("")
def get_leaderboard():
    return {"top10": _current_top10}


@api_router.get("/stream")
async def stream_leaderboard():
    async def generate():
        last_seq = -1
        while True:
            if _seq != last_seq:
                last_seq = _seq
                yield f"data: {json.dumps({'top10': _current_top10})}\n\n"
            await asyncio.sleep(0.5)

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------------------------------------------------------------------------
# Leaderboard HTML page
# ---------------------------------------------------------------------------

_HTML = """\
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bestenliste – NFC-Kasse</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{
  background:#09090b;color:#f4f4f5;
  font-family:'Segoe UI',system-ui,-apple-system,sans-serif;
  height:100vh;display:flex;flex-direction:column;overflow:hidden
}
header{
  text-align:center;padding:clamp(16px,3vh,32px) 20px clamp(10px,2vh,20px);
  border-bottom:1px solid #27272a;flex-shrink:0
}
header h1{
  font-size:clamp(1.6rem,5vw,3.2rem);font-weight:900;letter-spacing:.06em;
  color:#fbbf24;text-shadow:0 0 60px rgba(251,191,36,.35)
}
header .sub{font-size:clamp(.75rem,1.8vw,1.1rem);color:#52525b;margin-top:6px}
#board{
  flex:1;overflow:hidden;
  padding:clamp(10px,2vh,24px) clamp(12px,3vw,40px);
  display:flex;flex-direction:column;gap:clamp(5px,1.2vh,12px)
}
.entry{
  display:flex;align-items:center;
  gap:clamp(10px,2vw,24px);
  padding:clamp(10px,1.8vh,20px) clamp(14px,2.5vw,28px);
  border-radius:16px;background:#18181b;border:1px solid #27272a;
  flex-shrink:0;animation:slideIn .35s ease
}
.rank-1{
  background:linear-gradient(135deg,#1c1408,#2d1f06);
  border-color:#f59e0b;
  box-shadow:0 0 28px rgba(245,158,11,.14),inset 0 1px 0 rgba(245,158,11,.18)
}
.rank-2{
  background:linear-gradient(135deg,#141416,#1e1e22);
  border-color:#9ca3af;
  box-shadow:0 0 14px rgba(156,163,175,.07)
}
.rank-3{
  background:linear-gradient(135deg,#160d07,#231208);
  border-color:#cd7c2f;
  box-shadow:0 0 14px rgba(205,124,47,.07)
}
.badge{
  width:clamp(38px,5.5vw,64px);height:clamp(38px,5.5vw,64px);
  border-radius:50%;display:flex;align-items:center;justify-content:center;
  font-size:clamp(1rem,2.5vw,2rem);font-weight:900;flex-shrink:0;
  background:#27272a;color:#71717a
}
.rank-1 .badge{background:#f59e0b;color:#1c1408}
.rank-2 .badge{background:#9ca3af;color:#141416}
.rank-3 .badge{background:#cd7c2f;color:#160d07}
.name{
  flex:1;font-size:clamp(.95rem,3vw,2.1rem);font-weight:700;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#e4e4e7
}
.rank-1 .name{color:#fde68a}
.rank-2 .name{color:#f4f4f5}
.rank-3 .name{color:#fdba74}
.pts{
  font-size:clamp(1rem,3.2vw,2.3rem);font-weight:800;
  white-space:nowrap;color:#52525b;display:flex;align-items:baseline;gap:3px
}
.rank-1 .pts{color:#fbbf24}
.rank-2 .pts{color:#d1d5db}
.rank-3 .pts{color:#fb923c}
.pts-star{opacity:.55;font-size:.7em;margin-right:2px}
.pts-neg{color:#ef4444}
.empty{
  flex:1;display:flex;flex-direction:column;
  align-items:center;justify-content:center;
  color:#3f3f46;font-size:clamp(1rem,2.5vw,1.6rem);gap:16px
}
.empty-icon{font-size:clamp(3rem,10vw,7rem);opacity:.2}
@keyframes slideIn{from{opacity:0;transform:translateX(-16px)}to{opacity:1;transform:none}}
#offline{
  display:none;position:fixed;bottom:0;left:0;right:0;
  background:#7f1d1d;color:#fca5a5;text-align:center;
  padding:8px;font-size:.9rem
}
</style>
</head>
<body>
<header>
  <h1>&#127942; Bestenliste</h1>
  <div class="sub">Wer hat am meisten getrunken?</div>
</header>
<div id="board"></div>
<div id="offline">Verbindung unterbrochen &#8211; Wiederverbindung&#8230;</div>
<script>
const MEDALS=['\\u{1F947}','\\u{1F948}','\\u{1F949}'];

function esc(s){
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function render(top10){
  const board=document.getElementById('board');
  if(!top10||!top10.length){
    board.innerHTML='<div class="empty"><div class="empty-icon">&#127942;</div>Noch keine Teilnehmer &ndash; scannt euren Chip am Kiosk-Terminal!</div>';
    return;
  }
  board.innerHTML=top10.map((e,i)=>{
    const cls=i<3?'entry rank-'+(i+1):'entry';
    const badge=i<3?MEDALS[i]:String(e.rank);
    const neg=e.points<0?'<span class="pts-neg">&#8722;</span>':'';
    const abs=Math.abs(e.points);
    return '<div class="'+cls+'">'+
      '<div class="badge">'+badge+'</div>'+
      '<div class="name">'+esc(e.name)+'</div>'+
      '<div class="pts">'+neg+'<span class="pts-star">&#9733;</span>'+abs+'</div>'+
      '</div>';
  }).join('');
}

let es;
function connect(){
  document.getElementById('offline').style.display='none';
  es=new EventSource('/api/leaderboard/stream');
  es.onmessage=function(e){try{render(JSON.parse(e.data).top10);}catch(_){}};
  es.onerror=function(){
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


@router.get("/leaderboard", response_class=HTMLResponse)
def leaderboard_page():
    return HTMLResponse(content=_HTML)
