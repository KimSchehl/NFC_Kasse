import asyncio,sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
S=sys.argv[1]; OUT=f"{S}/out/features"; os.makedirs(OUT,exist_ok=True)
async def tapv(a,text):
    await a.pg.mouse.move(900,500)
    for _ in range(15):
        m=[l for l in await a.labels() if l[0].startswith(text) and l[1]=="button"]
        if m and 60<m[0][3]<1600: return await a.tapxy(m[0][2]+80,m[0][3]+min(m[0][5],40)/2)
        await a.pg.mouse.wheel(0,300); await a.pg.wait_for_timeout(500)
    raise Exception("tapv "+text)
async def main():
    async with async_playwright() as p:
        b=await browser(p)
        ctx=await b.new_context(viewport={"width":1280,"height":1700},device_scale_factor=1.5,locale="de-DE",has_touch=True)
        pg=await ctx.new_page(); a=App(pg,OUT); await a.login("admin","admin")
        await a.tap("Artikelverwaltung",role="button"); await pg.wait_for_timeout(1000)
        await tapv(a,"Bier 0,5 l"); await a.shot("l01_artikel_leaderboard_punkte"); await a.tap("Abbrechen"); await pg.mouse.move(900,500); await pg.mouse.wheel(0,-5000); await pg.wait_for_timeout(500)
        await tapv(a,"Steak im Brötchen"); await a.shot("p05_artikel_pager_erforderlich"); await a.tap("Abbrechen"); await pg.mouse.move(900,500); await pg.mouse.wheel(0,-5000); await pg.wait_for_timeout(500)
        await tapv(a,"Currywurst"); await a.shot("a01_artikel_mit_optionen")
        await pg.mouse.move(640,400); await pg.mouse.wheel(0,800); await a.shot("a02_artikel_mit_optionen_unten"); await a.tap("Abbrechen"); await pg.mouse.move(900,500); await pg.mouse.wheel(0,-5000); await pg.wait_for_timeout(500)
        ctx2=await b.new_context(viewport={"width":1280,"height":800},device_scale_factor=1.5,locale="de-DE",has_touch=True)
        pg2=await ctx2.new_page(); k=App(pg2,OUT); await k.login("kiosk","kiosk123")
        l=[x for x in await k.labels() if x[1]=="INPUT"][0]; await k.tapxy(l[2]+l[4]/3,l[3]+l[5]/2)
        await pg2.keyboard.type("04:77:88:9A"); await pg2.keyboard.press("Enter"); await pg2.wait_for_timeout(2500)
        await k.tap("Name bearbeiten",role="button"); await k.shot("l02_kiosk_leaderboard_anmelden")
        pg3=await b.new_page(viewport={"width":1920,"height":1080})
        await pg3.goto("http://nfc-kasse.lan:8000/leaderboard"); await pg3.wait_for_timeout(3000); await pg3.screenshot(path=f"{OUT}/l03_leaderboard_tv.png")
        await b.close()
asyncio.run(main())
