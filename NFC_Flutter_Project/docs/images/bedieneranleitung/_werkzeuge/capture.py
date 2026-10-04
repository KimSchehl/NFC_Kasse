import asyncio,sys,os,traceback; import os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from lib import *
S=sys.argv[1]; dev=sys.argv[2]
VP={"handy":({"width":412,"height":915},2.0),"tablet":({"width":1280,"height":800},1.5),"pc":({"width":1920,"height":1080},1.0)}[dev]
OUT=f"{S}/out/{dev}"; os.makedirs(OUT,exist_ok=True)
import time; NEWUID="04C0"+dev[:2].upper()+time.strftime("%H%M%S")
fails=[]
async def step(name,fn):
    try: await fn()
    except Exception as e: fails.append(name); print("FAIL",name,str(e)[:300])
async def main():
    async with async_playwright() as p:
        b=await browser(p)
        ctx=await b.new_context(viewport=VP[0],device_scale_factor=VP[1],locale="de-DE",is_mobile=(dev=="handy"),has_touch=(dev!="pc"))
        pg=await ctx.new_page(); a=App(pg,OUT)
        async def nav(label):
            if dev=="handy":
                await a.tap("Open navigation menu")
            await a.tap(label,role="button")
            if dev=="handy" and label=="Bearbeitungsmodus":
                await a.shot("10_bearbeitungsmodus_menue") if not os.path.exists(OUT+"/10_bearbeitungsmodus_menue.png") else None
                await pg.keyboard.press("Escape"); await pg.wait_for_timeout(800)
        async def scan(uid):
            if any(l[0]=="Feld leeren" for l in await a.labels()): await a.tap("Feld leeren",role="button")
            ls=[l for l in await a.labels() if l[1]=="INPUT"]
            l=ls[0]; await a.tapxy(l[2]+l[4]/3,l[3]+l[5]/2)
            await pg.keyboard.press("Control+A"); await pg.keyboard.type(uid); await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1500)
        async def s01():
            await pg.goto(URL); await pg.wait_for_timeout(6000); await a.sem(); await a.shot("01_anmeldung")
        await step("01",s01)
        await a.type_into("Benutzername","admin"); await a.type_into("Passwort","admin")
        await a.tap("Anmelden",role="button"); await pg.wait_for_timeout(3000); await a.sem()
        async def s02():
            await nav("Bar"); await a.shot("02_kasse_leer")
            if dev=="handy":
                await a.tap("Open navigation menu"); await a.shot("02b_menue_handy"); await pg.keyboard.press("Escape"); await pg.wait_for_timeout(500)
        await step("02",s02)
        async def s03():
            await pg.wait_for_timeout(1000); await a.tap("Bier 0,5 l",role="button"); await pg.wait_for_timeout(600); await a.tap("Radler 0,5 l",role="button"); await pg.wait_for_timeout(600); await a.tap("Cola 0,3 l",role="button")
            await scan("04A1B2C3"); await a.shot("03_warenkorb_mit_chip")
            await a.tap("Leeren",role="button")
        await step("03",s03)
        async def s04():
            await nav("Bonkasse"); await pg.wait_for_timeout(1000); await a.tap("Aufladen 20 €",role="button"); await scan(NEWUID); await a.shot("04_aufladen_neuer_chip_pfand")
            await a.tap("Buchen",role="button"); await a.shot("05_buchung_bestaetigt",wait=400)
            await pg.wait_for_timeout(2500); await a.tap("Letzte Buchung stornieren",role="button"); await a.shot("06_storno_dialog")
            await a.tap("Abbrechen")
        await step("04",s04)
        async def s07():
            await a.tap("Auszahlung",role="button"); await scan("04D4E5F6"); await a.shot("07_auszahlung")
            await a.tap("Leeren",role="button")
        await step("07",s07)
        async def s08():
            await nav("Essen"); await pg.wait_for_timeout(1000); await a.tap("Currywurst",role="button"); await a.shot("08_optionen_auswahl")
            await a.tap("Schließen")
        await step("08",s08)
        async def s09():
            await a.tap("Steak im Brötchen",role="button"); await a.tap("Bratwurst",role="button"); await scan("0477889A"); await a.shot("09_guthaben_reicht_nicht")
            await a.tap("Leeren",role="button")
        await step("09",s09)
        async def s10():
            await nav("Bearbeitungsmodus"); await a.shot("10_bearbeitungsmodus"); await nav("Bearbeitungsmodus")
        await step("10",s10)
        async def s11():
            await nav("Neue Kategorie"); await a.shot("11_neue_kategorie"); await a.tap("Abbrechen")
        await step("11",s11)
        async def s12():
            await a.tap("HILFE"); await a.shot("12_hilfe_anfordern"); await a.tap("Abbrechen")
        await step("12",s12)
        async def s13():
            await nav("Artikelverwaltung"); await a.shot("13_artikelverwaltung")
            await a.tap("Neuer Artikel"); await a.shot("14_artikel_neu_dialog"); await a.tap("Abbrechen")
        await step("13",s13)
        async def s15():
            await nav("Benutzer"); await a.shot("15_benutzerliste")
            l=await a.find("Anna (Bar)",role="group"); await a.tapxy(l[2]+l[4]-40,l[3]+l[5]/2); await a.shot("16_benutzer_bearbeiten")
            await pg.mouse.wheel(0,600); await a.shot("16b_benutzer_bearbeiten_kategorien"); await a.tap("Abbrechen")
        await step("15",s15)
        async def s17():
            await nav("Statistik"); await a.shot("17_statistik_uebersicht",wait=1500)
            await a.tap("Transaktionen"); await a.shot("18_statistik_transaktionen",wait=1500)
            await a.tap("Chips"); await a.shot("19_statistik_chips",wait=1500)
            await a.tap("Tagesabschluss",role="button"); await a.shot("20_tagesabschluss_dialog"); await a.tap("Abbrechen")
            await a.tap("Neues Event",role="button"); await a.shot("21_neues_event_dialog"); await a.tap("Abbrechen")
        await step("17",s17)
        async def s22():
            await nav("Einstellungen"); await a.shot("22_einstellungen_ueber")
            await a.tap("Design"); await a.shot("23_einstellungen_design")
            await a.tap("NFC-Lesegerät"); await a.shot("24_einstellungen_nfc_lesegeraet")
            await a.tap("Protokoll"); await a.shot("25_einstellungen_protokoll")
        await step("22",s22)
        async def s26():
            await nav("Protokolle"); await a.shot("26_protokolle",wait=1500)
        await step("26",s26)
        async def s27():
            await nav("Administrator"); await a.shot("27_konto")
        await step("27",s27)
        # kiosk
        async def s28():
            ctx2=await b.new_context(viewport=VP[0],device_scale_factor=VP[1],locale="de-DE",is_mobile=(dev=="handy"),has_touch=(dev!="pc"))
            pg2=await ctx2.new_page(); k=App(pg2,OUT); await k.login("kiosk","kiosk123"); await k.shot("28_kiosk_start")
            l=[x for x in await k.labels() if x[1]=="INPUT"][0]; await k.tapxy(l[2]+l[4]/3,l[3]+l[5]/2)
            await pg2.keyboard.type("04:D4:E5:F6"); await pg2.keyboard.press("Enter"); await k.shot("28b_kiosk_guthaben",wait=2500)
            print("\n".join(map(str,(await k.labels())[-15:])))
            await ctx2.close()
        await step("28",s28)
        if dev=="tablet":
            for path,name in [("/display","29_kundenanzeige_auswahl"),("/display/admin","30_kundenanzeige"),("/download","31_app_download")]:
                async def sx(path=path,name=name):
                    await pg.goto("http://nfc-kasse.lan:8000"+path); await a.shot(name,wait=2500)
                await step(name,sx)
        await b.close()
    print("FAILS",dev,fails)
asyncio.run(main())
