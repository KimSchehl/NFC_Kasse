import json,urllib.request,time
B="http://127.0.0.1:8000"
def req(m,p,body=None,tok=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body is not None else None,headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+tok} if tok else {})})
    t=urllib.request.urlopen(r).read(); return json.loads(t) if t else None
tok=req("POST","/api/auth/login",{"username":"admin","password":"admin"})["access_token"]
prods={}
for c in req("GET","/api/products/categories",None,tok):
    for p in req("GET",f"/api/products/?category_id={c['id']}",None,tok): prods[p["name"]]=p["id"]
print(list(prods)[:30])
for n,pts in [("Bier 0,5 l",10),("Radler 0,5 l",8),("Aperol Spritz",15),("Wasser 0,5 l",-5)]: req("PUT",f"/api/products/{prods[n]}",{"points":pts},tok)
for n in ["Currywurst","Steak im Brötchen","Pommes"]: req("PUT",f"/api/products/{prods[n]}",{"requires_pager":True},tok)
names={"04:A1:B2:C3":"Tobi","04:D4:E5:F6":"Sandra","04:77:88:9A":"Die Weinfreunde"}
for u,n in names.items(): req("PUT",f"/api/kiosk/chip/{u}/name",{"name":n,"leaderboard_opt_in":True},tok)
for u,items in [("04:A1:B2:C3",["Bier 0,5 l"]*3),("04:D4:E5:F6",["Aperol Spritz","Bier 0,5 l"]),("04:77:88:9A",["Radler 0,5 l"])]:
    req("POST","/api/sales/",{"nfc_uid":u,"product_ids":[prods[i] for i in items]},tok); time.sleep(2.1)
for u,pn in [("04:D4:E5:F6",7),("04:A1:B2:C3",12)]:
    req("POST","/api/sales/",{"nfc_uid":u,"product_ids":[prods["Currywurst"],prods["Pommes"]],"pager_number":pn},tok); time.sleep(2.1)
print(req("GET","/api/leaderboard"))
