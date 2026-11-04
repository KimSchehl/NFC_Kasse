import asyncio,sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
OUT=sys.argv[1]; os.makedirs(OUT,exist_ok=True)
async def main():
    async with async_playwright() as p:
        b=await browser(p)
        ctx=await b.new_context(viewport={"width":1280,"height":800},device_scale_factor=1.5,locale="de-DE",has_touch=True)
        pg=await ctx.new_page(); a=App(pg,OUT); await a.login("admin","admin")
        await a.tap("Bar",exact=True,role="button"); await pg.wait_for_timeout(1200)
        await a.tapxy(600,650); await pg.wait_for_timeout(800)
        for n in ["Weinschorle","Cola 0,3 l","Wasser 0,5 l"]:
            l=await a.find(n,role="button"); await a.tapxy(l[2]+l[4]/2,l[3]+l[5]-15); await pg.wait_for_timeout(1200)
        await a.shot("32_bondruck_warenkorb")
        await a.tap("Drucken",role="button"); await pg.wait_for_timeout(600)
        await a.shot("33_bons_gedruckt",wait=1300)
        await b.close()
asyncio.run(main())
