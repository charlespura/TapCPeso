import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const demo=path.join(root,'demo');
const scenes=JSON.parse(await fs.readFile(path.join(demo,'storyboard.json'),'utf8'));
const audio=await Promise.all(scenes.map((_,i)=>fs.readFile(path.join(demo,'audio',`scene-${i}.wav`))));
const data=`const DEMO_SCENES=${JSON.stringify(scenes)};\nconst DEMO_AUDIO=${JSON.stringify(audio.map(b=>b.toString('base64')))};\n`;
await fs.writeFile(path.join(demo,'demo-data.js'),data);
const html=await fs.readFile(path.join(demo,'video-source.html'),'utf8');
const motion=await fs.readFile(path.join(demo,'motion-graphics.js'),'utf8');
await fs.writeFile(path.join(demo,'tapcpeso-video.html'),html.replace('<script src="demo-data.js"></script>',`<script>${data}</script>`).replace('<script src="motion-graphics.js"></script>',`<script>${motion}</script>`));
const server=http.createServer(async(req,res)=>{
  try{
    const name=new URL(req.url,'http://localhost').pathname;
    const safe=name==='/'?'video-source.html':name.slice(1);
    if(!['video-source.html','demo-data.js','motion-graphics.js'].includes(safe)){res.writeHead(404);res.end();return}
    res.setHeader('Content-Type',safe.endsWith('.js')?'text/javascript':'text/html');
    res.end(await fs.readFile(path.join(demo,safe)));
  }catch(e){res.writeHead(500);res.end(e.message)}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const port=server.address().port;
const chrome=process.env.CHROME_PATH||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const browser=spawn(chrome,['--headless=new','--remote-debugging-port=9333',
  `--user-data-dir=${path.join(root,'.dart_tool','demo-chrome')}`,
  '--autoplay-policy=no-user-gesture-required','--no-first-run','--no-default-browser-check',
  '--disable-background-timer-throttling','--disable-renderer-backgrounding',
  '--disable-backgrounding-occluded-windows','--disable-features=Translate','about:blank'],
  {windowsHide:true,stdio:'ignore'});
let ws;
try {
  let version;
  for(let n=0;n<60;n++){
    try{version=await (await fetch('http://127.0.0.1:9333/json/version')).json();break}catch(e){await new Promise(r=>setTimeout(r,250))}
  }
  if(!version)throw Error('Headless Chrome could not start.');
  ws=new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
  let next=0;const pending=new Map();
  ws.onmessage=event=>{const result=JSON.parse(event.data);if(result.id&&pending.has(result.id)){
    const {resolve,reject}=pending.get(result.id);pending.delete(result.id);
    result.error?reject(Error(JSON.stringify(result.error))):resolve(result.result);
  }else if(result.method==='Runtime.exceptionThrown')console.error('Browser error:',JSON.stringify(result.params.exceptionDetails))};
  function call(method,params={},sessionId){return new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}))})}
  const {targetId}=await call('Target.createTarget',{url:`http://127.0.0.1:${port}/`});
  const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
  await call('Runtime.enable',{},sessionId);
  await call('Page.enable',{},sessionId);
  await call('Emulation.setDeviceMetricsOverride',{width:1360,height:900,deviceScaleFactor:1,mobile:false},sessionId);
  async function evaluate(expression){const result=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId);if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value}
  for(let n=0;n<60;n++){if(await evaluate('window.demoReady===true&&window.demoMotionVersion===2'))break;await new Promise(r=>setTimeout(r,100))}
  await fs.mkdir(path.join(demo,'previews'),{recursive:true});
  for(const time of [3,10,18,27,35,44,52,57]){
    const png=await evaluate(`window.demoRender(${time});document.getElementById('screen').toDataURL('image/png').split(',')[1]`);
    await fs.writeFile(path.join(demo,'previews',`scene-${time}.png`),Buffer.from(png,'base64'));
  }
  // Adjacent frames inside each scene must differ, beyond a slide transition.
  const motionChecks=await evaluate(`(()=>{const checks=[];for(const t of [3,10,18,27,35,44,52,57]){demoRender(t);const a=ctx.getImageData(600,70,620,530).data;demoRender(t+.25);const b=ctx.getImageData(600,70,620,530).data;let changed=0;for(let i=0;i<a.length;i+=4)if(Math.abs(a[i]-b[i])+Math.abs(a[i+1]-b[i+1])+Math.abs(a[i+2]-b[i+2])>12)changed++;checks.push({time:t,changedPixels:changed})}demoRender(0);return checks})()`);
  if(motionChecks.some(c=>c.changedPixels<50))throw Error('A scene has insufficient interface motion: '+JSON.stringify(motionChecks));
  console.log('Preview frames created. Recording 60 seconds of video with narration.');
  await evaluate('window.automationExport=true;window.demoRun(true).catch(e=>window.demoExportError=e.message);true');
  for(let n=0;n<180;n++){
    await new Promise(r=>setTimeout(r,500));
    const status=await evaluate('({ready:!!window.demoExportReady,error:window.demoExportError||null})');
    if(status.error)throw Error(status.error);
    if(status.ready)break;
    if(n===179)throw Error('Timed out recording demo.');
  }
  const info=await evaluate('({extension:window.demoExport.extension,mime:window.demoExport.mime,size:window.demoExport.size})');
  // Codec lists themselves contain commas; the base64 marker is the delimiter.
  const encoded=await evaluate(`new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result.slice(reader.result.indexOf('base64,')+7));reader.readAsDataURL(window.demoExport.blob)})`);
  const output=path.join(demo,`tapcpeso-demo.${info.extension}`);
  const videoBytes=Buffer.from(encoded,'base64');
  if(videoBytes.length!==info.size)throw Error('Encoded video transfer size mismatch.');
  await fs.writeFile(output,videoBytes);
  // Inspect the encoded artifact, not only its generating canvas.
  const qa=await evaluate(`new Promise(async(resolve,reject)=>{
    const v=document.createElement('video');v.preload='auto';v.muted=true;
    v.src=URL.createObjectURL(window.demoExport.blob);
    v.onloadedmetadata=()=>{v.currentTime=35};v.onerror=()=>reject(Error('Encoded video cannot play'));
    v.onseeked=()=>{const c=document.createElement('canvas');c.width=v.videoWidth;c.height=v.videoHeight;
      c.getContext('2d').drawImage(v,0,0);resolve({duration:v.duration,width:v.videoWidth,height:v.videoHeight,
        audioTracks:v.audioTracks?v.audioTracks.length:null,frame:c.toDataURL('image/png').split(',')[1]})};
  })`);
  await fs.writeFile(path.join(demo,'previews','encoded-video.png'),Buffer.from(qa.frame,'base64'));
  delete qa.frame;
  await fs.writeFile(path.join(demo,'verification.json'),JSON.stringify({...info,...qa,illustrated:true,motionVersion:2,motionChecks,brand:'TapCPeso green Material-style wallet UI',voice:'Microsoft Zira Desktop (synthetic)'},null,2));
  console.log(JSON.stringify({output,...info,...qa}));
  await call('Browser.close');
}finally{
  if(ws)ws.close();
  browser.kill();
  server.close();
}
