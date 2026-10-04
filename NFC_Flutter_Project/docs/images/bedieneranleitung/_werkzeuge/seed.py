import json, urllib.request
B="http://127.0.0.1:8000"
def req(m,p,body=None,tok=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body is not None else None,headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+tok} if tok else {})})
    try:
        with urllib.request.urlopen(r) as x:
            t=x.read(); return json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        print(m,p,e.code,e.read()[:300]); raise
tok=req("POST","/api/auth/login",{"username":"admin","password":"admin"})["access_token"]
cats={}
for i,n in enumerate(["Bonkasse","Bar","Essen"]):
    cats[n]=req("POST","/api/products/categories",{"name":n,"sort_order":i},tok)["id"]
P={}
def prod(c,n,p,**k):
    P[n]=req("POST","/api/products/",{"name":n,"price":p,"category_id":cats[c],**k},tok)["id"]
for v in [5,10,20,50]: prod("Bonkasse",f"Aufladen {v} €",-v,exclude_from_stats=True)
prod("Bonkasse","Auszahlung",0,is_payout=True,exclude_from_stats=True)
for n,p,s in [("Bier 0,5 l",4.0,None),("Radler 0,5 l",4.0,None),("Cola 0,3 l",2.5,None),("Wasser 0,5 l",2.0,None),("Weinschorle",3.5,None),("Aperol Spritz",6.0,40),("Becherpfand zurück",-2.0,None)]:
    prod("Bar",n,p,stock=s)
for n,p,s in [("Bratwurst",3.5,None),("Currywurst",4.5,None),("Pommes",3.0,None),("Steak im Brötchen",6.5,8),("Brezel",2.0,None)]:
    prod("Essen",n,p,stock=s)
P["mit Pommes"]=req("POST","/api/products/",{"name":"mit Pommes","price":7.0,"category_id":cats["Essen"],"group_id":P["Currywurst"]},tok)["id"]
u=req("POST","/api/users/",{"username":"anna","password":"anna123","display_name":"Anna (Bar)"},tok)["id"]
req("PUT",f"/api/users/{u}/categories",{"categories":[{"category_id":cats["Bar"],"can_book":True,"can_storno_5min":True},{"category_id":cats["Essen"],"can_book":True,"can_storno_5min":True}]},tok)
u2=req("POST","/api/users/",{"username":"bonkasse","password":"bonkasse1","display_name":"Bonkasse Eingang"},tok)["id"]
req("PUT",f"/api/users/{u2}/categories",{"categories":[{"category_id":cats["Bonkasse"],"can_book":True,"can_storno_5min":True}]},tok)
req("PUT",f"/api/users/{u2}/permissions",{"permission_ids":["help.receive"]},tok)
u3=req("POST","/api/users/",{"username":"kiosk","password":"kiosk123","display_name":"Kiosk"},tok)["id"]
req("PUT",f"/api/users/{u3}/permissions",{"permission_ids":["kiosk.access"]},tok)
import time
def book(uid,names):
    r=req("POST","/api/sales/",{"nfc_uid":uid,"product_ids":[P[n] for n in names]},tok); time.sleep(2.1); return r
book("04:A1:B2:C3",["Aufladen 20 €"]); book("04:D4:E5:F6",["Aufladen 50 €"]); book("04:77:88:9A",["Aufladen 10 €","Aufladen 5 €"])
book("04:A1:B2:C3",["Bier 0,5 l","Bier 0,5 l","Bratwurst"]); book("04:D4:E5:F6",["Aperol Spritz","Aperol Spritz","Currywurst"])
book("04:77:88:9A",["Cola 0,3 l","Pommes"]); book("04:D4:E5:F6",["Steak im Brötchen","Weinschorle"])
r=book("04:77:88:9A",["Brezel"]); req("POST",f"/api/sales/{r['sale_ids'][0]}/cancel",None,tok)
print("ok",cats,len(P))
