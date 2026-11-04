import asyncio,sys,os,json,urllib.request; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
OUT=sys.argv[1]; os.makedirs(OUT,exist_ok=True)
B="http://127.0.0.1:8000"
def req(m,p,body=None,tok=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body is not None else None,headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+tok} if tok else {})})
    t=urllib.request.urlopen(r).read(); return json.loads(t) if t else None
tok=req("POST","/api/auth/login",{"username":"admin","password":"admin"})["access_token"]
prods={}
for c in req("GET","/api/products/categories",None,tok):
    for p in req("GET",f"/api/products/?category_id={c['id']}",None,tok): prods[p["name"]]=p
async def main():
    async with async_playwright() as p:
        b=await browser(p)
        ctx=await b.new_context(viewport={"width":915,"height":412},device_scale_factor=2,locale="de-DE",is_mobile=True,has_touch=True)
        pg=await ctx.new_page()
        req("POST","/api/display/update",{"items":[]},tok)
        await pg.goto("http://nfc-kasse.lan:8000/display/admin"); await pg.wait_for_timeout(2500)
        await pg.screenshot(path=f"{OUT}/30a_kundenanzeige_warten.png")
        items=[{"name":"Bier 0,5 l","price":4.0,"quantity":2},{"name":"Bratwurst","price":3.5,"quantity":1}]
        bal=req("GET","/api/sales/balance/04:D4:E5:F6",None,tok)
        cur=bal.get("balance",20.5)
        req("POST","/api/display/update",{"items":items},tok); await pg.wait_for_timeout(1500)
        await pg.screenshot(path=f"{OUT}/30b_kundenanzeige_ohne_chip.png")
        req("POST","/api/display/update",{"items":items,"chip_uid":"04:D4:E5:F6","current_balance":cur,"balance_after":cur-11.5},tok); await pg.wait_for_timeout(1500)
        await pg.screenshot(path=f"{OUT}/30_kundenanzeige.png")
        req("POST","/api/sales/",{"nfc_uid":"04:D4:E5:F6","product_ids":[prods["Bier 0,5 l"]["id"]]*2+[prods["Bratwurst"]["id"]]},tok)
        await pg.wait_for_timeout(1600)
        await pg.screenshot(path=f"{OUT}/30c_kundenanzeige_bestaetigt.png")
        await b.close()
asyncio.run(main())
