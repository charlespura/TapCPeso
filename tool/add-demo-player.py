"""Keep the three local interactive entry points in sync, with a video overlay."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / 'demo' / 'interactive.html'
html = source.read_text(encoding='utf-8')
styles = '''
.watch-short{display:none}
#demo-dialog{padding:0;border:1px solid #73978240;border-radius:18px;background:#f5faf5;color:#173f34;width:min(1080px,94vw);max-width:none;max-height:94vh;overflow:auto;box-shadow:0 25px 100px #06201770}
#demo-dialog::backdrop{background:#071e18bf;backdrop-filter:blur(7px)}
.video-top{display:flex;align-items:flex-start;justify-content:space-between;padding:20px 23px 15px;gap:15px}.video-top h2{margin:0;font-size:17px;letter-spacing:-.4px}.video-top p{margin:5px 0 0;font-size:11px;color:#65796d}
.video-close{border-radius:8px;background:#e1ebe2;color:#173f34;padding:7px 12px;font-size:21px;line-height:1}
#walkthrough-video{display:block;width:100%;aspect-ratio:16/9;background:#102d26}
.video-foot{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:14px 23px 18px;font-size:11px;line-height:1.7;color:#62766c}.video-foot a{color:#006b59;font-weight:650;white-space:nowrap}
@media(max-width:610px){.watch-label{display:none}.watch-short{display:inline}.video-top{padding:14px}.video-top h2{font-size:15px}.video-foot{display:block;padding:12px 14px}.video-foot a{display:block;margin-top:7px}}
'''
dialog = '''
<dialog id="demo-dialog" aria-labelledby="video-title">
  <div class="video-top"><div><h2 id="video-title">How TapCPeso works</h2><p>A narrated, animated app walkthrough · 1 minute</p></div><button class="video-close" id="video-close" aria-label="Close demo video">×</button></div>
  <video id="walkthrough-video" controls playsinline preload="metadata" src="tapcpeso-demo.mp4" aria-label="TapCPeso animated wallet walkthrough"></video>
  <div class="video-foot"><span>TapCPeso UI preview · synthetic narration · QR/NFC and authentication shown as simulations.</span><a href="tapcpeso-demo.mp4" download>Download the MP4 ↗</a></div>
</dialog>
'''
script = '''
<script>
(()=>{
 const button=document.getElementById('watch-demo'),dialog=document.getElementById('demo-dialog'),video=document.getElementById('walkthrough-video');
 let resumeVoice=false;
 button.addEventListener('click',()=>{resumeVoice=document.getElementById('voice').getAttribute('aria-pressed')==='true';if(resumeVoice)document.getElementById('voice').click();dialog.showModal();video.currentTime=0;video.play().catch(()=>{});});
 document.getElementById('video-close').addEventListener('click',()=>dialog.close());
 dialog.addEventListener('click',event=>{const bounds=dialog.getBoundingClientRect();if(event.clientX<bounds.left||event.clientX>bounds.right||event.clientY<bounds.top||event.clientY>bounds.bottom)dialog.close();});
 dialog.addEventListener('close',()=>{video.pause();button.focus();resumeVoice=false;});
 video.addEventListener('error',()=>{document.querySelector('.video-top p').textContent='Keep tapcpeso-demo.mp4 beside this HTML file to watch the video.';});
})();
</script>
'''
if 'id="watch-demo"' not in html:
    html = html.replace('</style>', styles + '</style>', 1)
    html = html.replace('<div class="tools">', '<div class="tools"><button class="secondary" id="watch-demo">▶ <span class="watch-label">Watch 1-min demo</span><span class="watch-short">Demo</span></button>', 1)
    html = html.replace('</body>', dialog + script + '</body>')
source.write_text(html, encoding='utf-8')
for name in ('index.html', 'tapcpeso-demo.html'):
    source.with_name(name).write_text(html, encoding='utf-8')
print('TapCPeso in-page video player added; interactive entry points synchronized.')
