import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash,createHmac} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const browser=spawn(process.env.CHROME_PATH||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',[
  '--headless=new','--remote-debugging-port=9334',`--user-data-dir=${path.join(root,'.dart_tool','interactive-chrome')}`,
  '--no-first-run','--no-default-browser-check','--disable-background-timer-throttling','about:blank'],
  {windowsHide:true,stdio:'ignore'});
let ws;
try{
  let version;for(let i=0;i<60;i++){try{version=await(await fetch('http://127.0.0.1:9334/json/version')).json();break}catch(e){await new Promise(r=>setTimeout(r,250))}}
  if(!version)throw Error('Chrome failed to launch');
  ws=new WebSocket(version.webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
  let id=0;const pending=new Map(),errors=[];
  ws.onmessage=event=>{const r=JSON.parse(event.data);if(r.id&&pending.has(r.id)){const p=pending.get(r.id);pending.delete(r.id);r.error?p.reject(Error(JSON.stringify(r.error))):p.resolve(r.result)}else if(r.method==='Runtime.exceptionThrown')errors.push(r.params.exceptionDetails)};
  const call=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const n=++id;pending.set(n,{resolve,reject});ws.send(JSON.stringify({id:n,method,params,...(sessionId?{sessionId}:{})}))});
  const {targetId}=await call('Target.createTarget',{url:pathToFileURL(path.join(root,'demo','index.html')).href});
  const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
  await call('Runtime.enable',{},sessionId);await call('Page.enable',{},sessionId);
  await call('Emulation.setDeviceMetricsOverride',{width:1440,height:1050,deviceScaleFactor:1,mobile:false},sessionId);
  async function ev(expression){const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId);if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value}
  for(let i=0;i<40;i++){if(await ev('!!window.TapDemo'))break;await new Promise(r=>setTimeout(r,100))}
  const check=async(expression,message)=>{if(!await ev(expression))throw Error(message)};
  const click=async(k,a)=>{await ev(`document.querySelector('[data-phone="${k}"] [data-action="${a}"]').click();true`);await new Promise(r=>setTimeout(r,20))};
  const form=async(k,kind,values)=>{await ev(`(()=>{const f=document.querySelector('[data-phone="${k}"] form[data-form="${kind}"]');for(const [name,value]of Object.entries(${JSON.stringify(values)}))f.elements.namedItem(name).value=value;f.requestSubmit();return true})()`);await new Promise(r=>setTimeout(r,20))};
  const balance=(k,m)=>`TapDemo.snapshot().devices.${k}.users.find(u=>u.mobile==='${m}').balance`;
  const a=balance('A','09171111111'),b=balance('B','09172222222');
  const snap=()=>ev('TapDemo.snapshot()');
  for(const input of ['', 'abc','a'.repeat(100),'é peso']){
    const actual=await ev(`TapDemo.sha(${JSON.stringify(input)})`),expected=createHash('sha256').update(input).digest('hex');
    if(actual!==expected)throw Error('SHA256 mismatch');
    const mac=await ev(`TapDemo.hmac(${JSON.stringify(input)})`);
    if(mac!==createHmac('sha256','TapCPeso-browser-demo-only-v1').update(input).digest('hex'))throw Error('HMAC mismatch');
  }
  await ev('document.getElementById("start").click()');await check(`${a}===100000&&${b}===100000`,'Demo setup failed');
  await click('A','cashin');await form('A','cashin',{amount:'100.00'});await check(`${a}===110000&&${b}===100000`,'Cash-in affected wrong wallet');
  await click('A','send');await form('A','send',{receiver:'09172222222',amount:'999999'});await check(`${a}===110000&&TapDemo.snapshot().devices.A.modal===null`,'Insufficient funds accepted');
  await form('A','send',{receiver:'09172222222',amount:'25.00'});await form('A','pin',{pin:'0000'});await check(`TapDemo.snapshot().devices.A.modal.type==='pin'&&${a}===110000`,'Wrong PIN accepted');
  await form('A','pin',{pin:'1234'});await click('A','cancel');await check(`${a}===110000&&TapDemo.snapshot().devices.A.ledger.length===0`,'Cancel debited wallet');
  await form('A','send',{receiver:'09172222222',amount:'25.00'});await form('A','pin',{pin:'1234'});await click('A','approve');await check(`${a}===107500`,'Sender not debited correctly');
  const payment=(await snap()).devices.A.outgoing;
  await click('A','qr');await check(`${a}===107500&&${b}===100000`,'Delivery changes balances before receipt');
  await click('B','accept');await check(`${b}===102500`,'Receiver not credited');
  await click('A','nfc');await click('B','accept');await check(`${b}===102500&&TapDemo.snapshot().devices.B.receipts.length===1`,'Replay credited twice');
  await click('B','home');await click('B','receive');const changed={...payment,cents:2600};
  const token={demo_version:changed.demo_version,tx_id:changed.tx_id,sender:changed.sender,receiver:changed.receiver,cents:changed.cents,timestamp:changed.timestamp,signature_token:changed.signature_token};
  await form('B','paste',{payload:JSON.stringify(token)});await check(`${b}===102500&&TapDemo.snapshot().devices.B.toast.text.includes('Signature invalid')`,'Tampering accepted');
  await click('B','switch');await form('B','switch',{mobile:'09171111111',pin:'1234'});await click('A','qr');await click('B','accept');await check(`TapDemo.snapshot().devices.B.toast.text.includes('Wrong recipient')`,'Wrong recipient accepted');
  await click('B','switch');await form('B','switch',{mobile:'09172222222',pin:'1234'});
  await click('A','home');await click('A','sync');await click('B','sync');await check(`${a}===107500&&${b}===102500`,'Sync changes balances');
  await check(`TapDemo.snapshot().devices.A.ledger.every(t=>t.status==='SYNCED')&&TapDemo.snapshot().devices.B.ledger.every(t=>t.status==='SYNCED')`,'Sync failed');
  await check('TapDemo.snapshot().completed.length===6','Guide did not complete');
  await fs.mkdir(path.join(root,'demo','previews'),{recursive:true});
  await ev('document.querySelectorAll(".toast").forEach(e=>e.remove())');
  const shot=await call('Page.captureScreenshot',{format:'png'},sessionId);await fs.writeFile(path.join(root,'demo','previews','interactive-desktop.png'),Buffer.from(shot.data,'base64'));
  await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true},sessionId);
  await check('document.documentElement.scrollWidth<=390','Mobile page overflows horizontally');
  await ev('document.querySelector("[data-tab=B]").click();document.querySelector(".mobile-tabs").scrollIntoView()');
  await check('getComputedStyle(document.querySelector("[data-device=A]")).display==="none"&&getComputedStyle(document.querySelector("[data-device=B]")).display!=="none"','Mobile phone switch failed');
  const mobileShot=await call('Page.captureScreenshot',{format:'png'},sessionId);await fs.writeFile(path.join(root,'demo','previews','interactive-mobile.png'),Buffer.from(mobileShot.data,'base64'));
  await ev('document.getElementById("reset").click()');await check('TapDemo.snapshot().devices.A.users.length===0&&TapDemo.snapshot().devices.B.ledger.length===0','Reset failed');
  await click('A','register-tab');await form('A','auth',{name:'Test User',mobile:'09173333333',pin:'9876'});await check(`TapDemo.snapshot().devices.A.current==='09173333333'`,'Registration failed');
  await click('A','cashin');await form('A','cashin',{amount:'0.01'});await check(`TapDemo.snapshot().devices.A.users[0].balance===1`,'Cent cash-in failed');
  await click('A','send');await ev('document.querySelector("[data-phone=A] input[name=amount]").value="17.25"');
  await new Promise(r=>setTimeout(r,6700));
  await check('document.querySelector("[data-phone=A] input[name=amount]").value==="17.25"','Toast expiry cleared an in-progress form');
  await click('A','home');await click('A','cashin');
  await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27},sessionId);
  await call('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27},sessionId);
  await check('TapDemo.snapshot().devices.A.modal===null','Escape did not dismiss modal');
  await ev('document.getElementById("watch-demo").click()');
  await check('document.getElementById("demo-dialog").open','Video overlay did not open');
  for(let i=0;i<50;i++){if(await ev('document.getElementById("walkthrough-video").readyState>=2'))break;await new Promise(r=>setTimeout(r,100))}
  await check('document.getElementById("walkthrough-video").readyState>=2','Video cannot decode in overlay');
  await check('document.documentElement.scrollWidth<=390','Video button causes mobile overflow');
  await ev('document.getElementById("video-close").click()');
  await check('!document.getElementById("demo-dialog").open&&document.getElementById("walkthrough-video").paused','Video did not pause on close');
  if(errors.length)throw Error(JSON.stringify(errors));
  const report={passed:true,checks:['SHA256/HMAC vs Node crypto','demo accounts','cash-in isolation','insufficient funds','wrong PIN','cancellation','single debit','QR delivery','NFC replay','signature tampering','recipient binding','independent sync','guide completion','mobile width and tabs','reset','registration','one-cent amount','form survives toast expiry','Escape dismisses modal','video overlay opens and decodes','video stops on close','mobile video button layout'],screenshots:['interactive-desktop.png','interactive-mobile.png'],browserExceptions:errors};
  await fs.writeFile(path.join(root,'demo','interactive-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
  await call('Browser.close');
}finally{if(ws)ws.close();browser.kill()}
