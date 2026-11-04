import asyncio,sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
OUT=sys.argv[1]; os.makedirs(OUT,exist_ok=True)
async def main():
    async with async_playwright() as p:
        b=await browser(p)
        ctx=await b.new_context(viewport={"width":1280,"height":800},device_scale_factor=1.5,locale="de-DE",has_touch=True)
        pg=await ctx.new_page(); a=App(pg,OUT); await a.login("admin","admin")
        await a.tap("Essen",exact=True,role="button"); await pg.wait_for_timeout(2000)
        await a.shot("01_kasse_mit_pagerliste")
        l=await a.find("Steak im Brötchen",role="button"); await a.tapxy(l[2]+l[4]/2,l[3]+l[5]-15); await pg.wait_for_timeout(800)
        l=[x for x in await a.labels() if x[1]=="INPUT"][0]; await a.tapxy(l[2]+l[4]/3,l[3]+l[5]/2)
        await pg.keyboard.type("04A1B2C3"); await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1500)
        await a.tap("Buchen",role="button"); await pg.wait_for_timeout(1000)
        await pg.keyboard.type("3"); await a.shot("02_pager_zuweisen")
        await a.tap("Pager zuweisen",role="button"); await pg.wait_for_timeout(2500)
        await a.shot("03_pagerliste_neuer_eintrag")
        await a.tap("Fertig",role="button"); await a.shot("04_pager_fertig_bestaetigen",wait=300)
        await b.close()
asyncio.run(main())
