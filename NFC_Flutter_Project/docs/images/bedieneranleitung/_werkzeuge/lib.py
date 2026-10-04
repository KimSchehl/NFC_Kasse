import asyncio
from playwright.async_api import async_playwright
URL="http://nfc-kasse.lan:8000/webapp/"
class App:
    def __init__(s,pg,out): s.pg=pg; s.out=out
    async def sem(s):
        el=await s.pg.query_selector("flt-semantics-placeholder")
        if el: await el.dispatch_event("click"); await s.pg.wait_for_timeout(800)
    async def labels(s):
        return await s.pg.evaluate("""Array.from(document.querySelectorAll('flt-semantics, flt-semantics input, flt-semantics textarea')).map(e=>{const r=e.getBoundingClientRect();return [(e.getAttribute('aria-label')||e.innerText||'').trim().replace(/\\n/g,' | '),e.getAttribute('role')||e.tagName,Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)]}).filter(a=>a[0]&&a[4]>0)""")
    async def find(s,text,exact=False,nth=0,role=None):
        for _ in range(20):
            ls=await s.labels()
            m=[l for l in ls if (l[0]==text if exact else text in l[0]) and (role is None or l[1]==role)]
            m.sort(key=lambda l:l[4]*l[5])
            if len(m)>nth: return m[nth]
            await s.pg.wait_for_timeout(300)
        raise Exception("not found: "+text+"\n"+"\n".join(map(str,ls)))
    async def tap(s,text,**k):
        l=await s.find(text,**k)
        await s.pg.mouse.click(l[2]+l[4]/2,l[3]+l[5]/2); await s.pg.wait_for_timeout(700)
    async def tapxy(s,x,y): await s.pg.mouse.click(x,y); await s.pg.wait_for_timeout(700)
    async def type_into(s,label,text,enter=False):
        await s.tap(label)
        await s.pg.keyboard.press("Control+A"); await s.pg.keyboard.type(text)
        if enter: await s.pg.keyboard.press("Enter")
        await s.pg.wait_for_timeout(600)
    async def shot(s,name,wait=900):
        await s.pg.wait_for_timeout(wait)
        await s.pg.screenshot(path=f"{s.out}/{name}.png")
    async def login(s,user,pw):
        await s.pg.goto(URL); await s.pg.wait_for_timeout(6000); await s.sem()
        await s.type_into("Benutzername",user); await s.type_into("Passwort",pw)
        await s.tap("Anmelden",role="button"); await s.pg.wait_for_timeout(3000); await s.sem()
async def browser(p):
    return await p.chromium.launch(executable_path="/opt/pw-browsers/chromium-1194/chrome-linux/chrome",args=["--host-resolver-rules=MAP nfc-kasse.lan 127.0.0.1"])
