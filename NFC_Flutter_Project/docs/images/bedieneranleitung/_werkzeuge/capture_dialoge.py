import asyncio,sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
S=sys.argv[1]; OUT=f"{S}/out/features"; os.makedirs(OUT,exist_ok=True)
async def tapv(a,text):
    m=[l for l in await a.labels() if l[0].startswith(text) and l[1]=="button"]
    await a.tapxy(m[0][2]+80,m[0][3]+min(m[0][5],40)/2)
async def clipshot(a,title,name):
    await a.pg.wait_for_timeout(900)
    ls=await a.labels()
    t=[l for l in ls if l[0]==title][0]; sv=[l for l in ls if l[0]=="Speichern" and l[1]=="button"][0]
    x0=t[2]-24; y0=t[3]-24; ins=[l for l in ls if l[1]=="INPUT"]; x1=max([sv[2]+sv[4]]+[l[2]+l[4] for l in ins])+24; y1=sv[3]+sv[5]+24
    await a.pg.screenshot(path=f"{OUT}/{name}.png",clip={"x":x0,"y":y0,"width":x1-x0,"height":y1-y0})
async def main():
    async with async_playwright() as p:
        b=await browser(p)
        ctx=await b.new_context(viewport={"width":1280,"height":1700},device_scale_factor=2,locale="de-DE",has_touch=True)
        pg=await ctx.new_page(); a=App(pg,OUT); await a.login("admin","admin")
        await a.tap("Artikelverwaltung",role="button"); await pg.wait_for_timeout(1000)
        for art,name in [("Currywurst","a01_artikel_mit_optionen"),("Bier 0,5 l","l01_artikel_leaderboard_punkte"),("Steak im Brötchen","p05_artikel_pager_erforderlich")]:
            await tapv(a,art); await clipshot(a,"Artikel bearbeiten",name); await a.tap("Abbrechen")
        # new article dialog
        await a.tap("Neuer Artikel"); await clipshot(a,"Neuer Artikel","a00_artikel_neu"); await a.tap("Abbrechen")
        await b.close()
asyncio.run(main())
