import json,urllib.request
B="http://127.0.0.1:8000"
def req(m,p,body=None,tok=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body is not None else None,headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+tok} if tok else {})})
    t=urllib.request.urlopen(r).read(); return json.loads(t) if t else None
tok=req("POST","/api/auth/login",{"username":"admin","password":"admin"})["access_token"]
cats={c["name"]:c for c in req("GET","/api/products/categories",None,tok)}
for n,col in [("Bonkasse","#2E7D32"),("Bar","#1565C0"),("Essen","#EF6C00")]:
    req("PUT",f"/api/products/categories/{cats[n]['id']}",{"name":n,"color":col},tok)
prods={}
for c in cats.values():
    for p in req("GET",f"/api/products/?category_id={c['id']}",None,tok): prods[p["name"]]=p
req("PUT",f"/api/products/{prods['mit Pommes']['id']}",{"color":"#F9A825"},tok)
req("POST","/api/products/",{"name":"pur","price":4.5,"category_id":cats["Essen"]["id"],"group_id":prods["Currywurst"]["id"],"color":"#C62828"},tok)
for n,col in [("Bier 0,5 l","#F9A825"),("Radler 0,5 l","#FBC02D"),("Aperol Spritz","#EF6C00"),("Weinschorle","#AD1457"),("Currywurst","#EF6C00"),("Bratwurst","#8D6E63")]:
    req("PUT",f"/api/products/{prods[n]['id']}",{"color":col},tok)
for n,pts in [("Bier 0,5 l",10),("Radler 0,5 l",8),("Aperol Spritz",15),("Wasser 0,5 l",-5)]:
    req("PUT",f"/api/products/{prods[n]['id']}",{"points":pts},tok)
for n in ["Currywurst","Steak im Brötchen","Pommes"]:
    req("PUT",f"/api/products/{prods[n]['id']}",{"requires_pager":True},tok)
print("extra ok")
