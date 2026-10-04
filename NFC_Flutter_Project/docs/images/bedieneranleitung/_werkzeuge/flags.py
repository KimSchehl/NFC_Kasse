import asyncio,sys; import os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
async def main():
    async with async_playwright() as p:
        b=await browser(p); pg=await b.new_page(viewport={"width":1280,"height":720},locale="de-DE")
        await pg.goto("chrome://flags/#unsafely-treat-insecure-origin-as-secure"); await pg.wait_for_timeout(2500)
        await pg.fill("#unsafely-treat-insecure-origin-as-secure textarea","http://nfc-kasse.lan:8000, http://192.168.1.2:8000"); await pg.select_option("#unsafely-treat-insecure-origin-as-secure select","1") if False else None
        sel=pg.locator("#unsafely-treat-insecure-origin-as-secure select"); opts=await sel.locator("option").all_text_contents(); print(opts); await sel.select_option(label="Enabled"); await pg.wait_for_timeout(1500)
        os.makedirs(sys.argv[1]+"/out",exist_ok=True); await pg.screenshot(path=sys.argv[1]+"/out/flags.png")
        await b.close()
asyncio.run(main())
