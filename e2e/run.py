# End-to-end test of the Zrzutka web app against a local ganache chain (chainId 8453).
# Wallet = injected EIP-1193 shim announced via EIP-6963; RPC calls to Base are routed to ganache.
import asyncio, json, re, urllib.request, os, shutil
from playwright.async_api import async_playwright
ENV=json.load(open("e2e/env.json")); A=ENV["accounts"]
def rpc(method, params=[]):
    req=urllib.request.Request("http://127.0.0.1:8545",data=json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params}).encode(),headers={"content-type":"application/json"})
    return json.loads(urllib.request.urlopen(req).read()).get("result")
SHIM="""(()=>{const ACC='%s';const eth={isMetaMask:true,on(){},removeListener(){},request:async({method,params})=>{
 if(method==='eth_requestAccounts'||method==='eth_accounts')return [ACC]; if(method==='eth_chainId')return '0x2105';
 if(method==='wallet_switchEthereumChain'||method==='wallet_addEthereumChain')return null;
 if(method==='eth_signTypedData_v4'&&typeof params[1]==='string')params=[params[0],JSON.parse(params[1])]; /* ganache wants an object, MetaMask a string */
 const r=await fetch('https://mainnet.base.org/',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:Date.now(),method,params:params||[]})});
 const j=await r.json(); if(j.error){const e=new Error(j.error.message);e.code=j.error.code;e.data=j.error.data;throw e;} return j.result;}};
 window.ethereum=eth; const ann=()=>window.dispatchEvent(new CustomEvent("eip6963:announceProvider",{detail:Object.freeze({info:{uuid:"mm-1",name:"MetaMask",icon:"",rdns:"io.metamask"},provider:eth})}));
 window.addEventListener("eip6963:requestProvider",ann); ann(); })();"""
async def route_rpc(route):
    body=route.request.post_data
    req=urllib.request.Request("http://127.0.0.1:8545",data=body.encode(),headers={"content-type":"application/json"})
    data=await asyncio.get_event_loop().run_in_executor(None, lambda: urllib.request.urlopen(req).read())
    await route.fulfill(status=200,content_type="application/json",body=data,headers={"access-control-allow-origin":"*"})
RPCRE=re.compile(r"https://(mainnet\.base\.org|base-rpc\.publicnode\.com|base\.llamarpc\.com).*")
def site(path, addr=None):
    h=open("index.html").read().replace("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",ENV["usdc"])
    if addr: h=h.replace('"__CONTRACT_ADDRESS__"',json.dumps(addr))
    os.makedirs(os.path.dirname(path),exist_ok=True); open(path,"w").write(h); shutil.copy("ethers.umd.min.js",os.path.join(os.path.dirname(path),"ethers.umd.min.js"))
async def mk(br, acc, url, errs, name, mobile=False):
    ctx=await br.new_context(viewport={"width":390,"height":844} if mobile else {"width":1240,"height":860},is_mobile=mobile,has_touch=mobile,locale="pl-PL")
    if acc: await ctx.add_init_script(SHIM%acc)
    await ctx.route(RPCRE, route_rpc)
    p=await ctx.new_page()
    p.on("pageerror", lambda e: errs.append(f"{name}: {e}"))
    p.on("console", lambda m: errs.append(f"{name} console.{m.type}: {m.text}") if m.type in ("error","warning") else None)
    p.on("dialog", lambda d: asyncio.ensure_future(d.accept(DLG.get(name,"7"))))
    await p.goto(url); return p
DLG={}; ERRL=[]
async def ok(p, what, timeout=30000):
    try: el=await p.wait_for_selector(".toast.ok, .toast.err",timeout=timeout)
    except Exception:
        print("DEBUG errs", ERRL[-5:]); print("DEBUG", what, await p.evaluate("({toasts:document.getElementById('toasts').innerText,hint:document.getElementById('hint').textContent,url:location.href})")); raise
    txt=await el.inner_text()
    if "err" in (await el.get_attribute("class")): raise Exception(f"{what} FAILED: {txt}")
    print("  ✓",what,"→",txt.strip())
    await p.evaluate("document.querySelectorAll('.toast').forEach(t=>t.remove())")
async def main():
    errs=ERRL; B="http://localhost:8002/e2e/"
    site("e2e/setup/index.html")
    async with async_playwright() as pw:
        br=await pw.chromium.launch()
        # 1. owner deploys from the setup screen
        o=await mk(br,A[0],B+"setup/index.html",errs,"owner")
        await o.wait_for_selector("#vSetup:not(.hidden)"); await o.screenshot(path="e2e/01_setup.png")
        await o.click("#btnDeploy"); await o.wait_for_selector("#deployResult:not(.hidden)",timeout=60000)
        addr=(await o.inner_text("#deployedAddr")).strip(); print("deployed:",addr)
        site("e2e/site/index.html",addr); APP=B+"site/index.html"
        # 2. guest view (no wallet)
        g=await mk(br,None,APP,errs,"guest"); await g.wait_for_selector("#vHome:not(.hidden)"); await g.wait_for_timeout(1200)
        print("guest home:", (await g.inner_text("#list")).strip()[:60]); await g.screenshot(path="e2e/02_home_empty.png",full_page=True)
        # 3. creator: profile name + campaign
        c=await mk(br,A[1],APP,errs,"creator"); await c.wait_for_selector("#vHome:not(.hidden)"); await c.wait_for_timeout(1000)
        await c.click("#acct"); await c.wait_for_selector("#vMe:not(.hidden)"); await c.fill("#pName","Kasia z Lublina"); await c.click("#bName"); await ok(c,"setProfileName")
        await c.click("#brand"); await c.click("#btnNew"); await c.wait_for_selector("#vCreate:not(.hidden)")
        await c.fill("#fTitle","Wyjazd klasowy do Zakopanego"); await c.fill("#fDesc","Zbieramy na autokar i nocleg dla 3b.\nJeśli nie uzbieramy — każdy dostaje zwrot."); await c.fill("#fLink","https://example.com/wyjazd")
        await c.fill("#fGoal","50"); await c.fill("#fDays","14"); await c.dispatch_event("#fDays","input")
        print("preview:", await c.inner_text("#fPreview")); await c.screenshot(path="e2e/03_create.png",full_page=True)
        await c.click("#btnCreate"); await ok(c,"createCampaign"); await c.wait_for_selector("#vCamp:not(.hidden)"); await c.wait_for_timeout(1500)
        print("campaign url:", c.url)
        await c.fill("#updText","Autokar zarezerwowany! 🚌"); await c.click("#bPostUpd"); await ok(c,"postUpdate")
        CAMP=APP+"?c=1"
        # 4. backers: permit contributions with messages + social actions
        b1=await mk(br,A[2],CAMP,errs,"b1"); await b1.wait_for_selector("#vCamp:not(.hidden)"); await b1.wait_for_timeout(1500)
        await b1.fill("#gAmount","30"); await b1.fill("#gMsg","Powodzenia! 💙"); await b1.click("#bGive"); await ok(b1,"contributeWithPermit 30")
        await b1.wait_for_timeout(1200); await b1.click("#bUp"); await ok(b1,"upvote")
        await b1.wait_for_timeout(800); await b1.click("#bFollow"); await ok(b1,"follow")
        await b1.screenshot(path="e2e/04_campaign_backed.png",full_page=True)
        b2=await mk(br,A[3],CAMP,errs,"b2"); await b2.wait_for_selector("#vCamp:not(.hidden)"); await b2.wait_for_timeout(1500)
        await b2.click("#amts button:has-text('$25')"); await b2.click("#bGive"); await ok(b2,"contributeWithPermit 25")
        DLG["b2"]="Test zgłoszenia"; await b2.wait_for_timeout(1000); await b2.click("#bReport"); await ok(b2,"report")
        # 5. creator claims
        await c.goto(CAMP); await c.wait_for_selector("#boxCreator:not(.hidden)",timeout=15000); await c.wait_for_timeout(800)
        await c.screenshot(path="e2e/05_creator_goal.png",full_page=True)
        await c.click("#bClaim"); await ok(c,"claim")
        bal=int(rpc("eth_call",[{"to":ENV["usdc"],"data":"0x70a08231"+A[1][2:].lower().rjust(64,"0")},"latest"]),16)
        print("  creator USDC:", bal/1e6, "(1000 + 55 - 1% fee)")
        # 6. backers mint badges
        await b1.goto(CAMP); await b1.wait_for_selector("#bBadge",timeout=15000); await b1.click("#bBadge"); await ok(b1,"mintBadge")
        await b1.wait_for_timeout(1500); print("  after mint:", (await b1.inner_text("#boxMine")).replace("\n"," | "))
        await b1.goto(APP+"?p=me"); await b1.wait_for_selector("#myBadges img",timeout=20000); await b1.wait_for_timeout(800)
        await b1.screenshot(path="e2e/06_badges.png",full_page=True)
        # 7. second campaign: extend, edit, contribution, cancel, refund
        await c.goto(APP+"?p=new"); await c.wait_for_selector("#vCreate:not(.hidden)")
        await c.fill("#fTitle","Nowy dach dla świetlicy"); await c.fill("#fDesc","Remont dachu świetlicy wiejskiej."); await c.fill("#fGoal","500")
        await c.click("#btnCreate"); await ok(c,"createCampaign #2"); await c.wait_for_timeout(1500)
        DLG["creator"]="7"; await c.click("#bExtend"); await ok(c,"extendDeadline +7")
        DLG["creator"]="Remont dachu świetlicy — mamy już wycenę od dekarza."; await c.wait_for_timeout(800); await c.click("#bEdit"); await ok(c,"editCampaign")
        b3=await mk(br,A[4],APP+"?c=2",errs,"b3"); await b3.wait_for_selector("#vCamp:not(.hidden)"); await b3.wait_for_timeout(1500)
        await b3.fill("#gAmount","12.5"); await b3.click("#bGive"); await ok(b3,"contribute 12.5")
        await c.goto(APP+"?c=2"); await c.wait_for_selector("#boxCreator:not(.hidden)"); await c.wait_for_timeout(800); await c.click("#bCancel"); await ok(c,"cancel")
        await b3.goto(APP+"?c=2"); await b3.wait_for_selector("#bRefund",timeout=15000); await b3.click("#bRefund"); await ok(b3,"refund")
        await b3.wait_for_timeout(1500); print("  refund box:", (await b3.inner_text("#boxMine")).replace("\n"," | "))
        # 8. home lists + mobile
        await g.goto(APP); await g.wait_for_selector("#vHome:not(.hidden)"); await g.wait_for_timeout(1500); await g.click("#tabs [data-t='success']"); await g.wait_for_selector(".cc"); await g.wait_for_timeout(1000)
        print("success tab:", (await g.inner_text("#list")).replace("\n"," | ")[:160]); await g.screenshot(path="e2e/07_home_success.png",full_page=True)
        m=await mk(br,A[5],CAMP,errs,"mobile",mobile=True); await m.wait_for_selector("#vCamp:not(.hidden)"); await m.wait_for_timeout(2000); await m.screenshot(path="e2e/08_mobile.png",full_page=True)
        # 9. admin
        await o.goto(APP+"?p=admin"); await o.wait_for_selector("#vAdmin:not(.hidden)"); await o.wait_for_timeout(2500)
        print("admin:", (await o.inner_text("#vAdmin .kpis")).replace("\n"," "))
        await o.fill("#aFeeIn","2"); await o.click("#aFeeSave"); await ok(o,"setFee 2%")
        await o.click("#aPauseBtn"); await ok(o,"pause"); await o.wait_for_timeout(1000); await o.click("#aPauseBtn"); await ok(o,"unpause")
        await o.screenshot(path="e2e/09_admin.png",full_page=True)
        # non-owner can't see admin chip
        print("admin chip hidden for backer:", await b1.is_hidden("#adminChip"))
        # EN
        await g.click("#langChip"); await g.wait_for_timeout(800); print("EN hero:", await g.inner_text("h1"))
        print("permit nonces b1,b2,b3:", [int(rpc("eth_call",[{"to":ENV["usdc"],"data":"0x7ecebe00"+a[2:].lower().rjust(64,"0")},"latest"]),16) for a in A[2:5]])
        print("ERRORS:", errs)

        await br.close()
asyncio.run(main())
