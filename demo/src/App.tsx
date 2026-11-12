import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import type { FormEvent, InputHTMLAttributes, ReactNode } from 'react';
import type { Device, DeviceId, Payment, WalletState } from './types';
import { currentUser, money, parse, payload, steps, titles, wallet } from './wallet';
import { amount, hmac, shaText } from './crypto';

const videoUrl = `${import.meta.env.BASE_URL}tapcpeso-demo.mp4`;
type Run = (work: () => void | Promise<void>) => void;
function Button({ children, action, onClick, className = 'primary', ...rest }: { children: ReactNode; action: string; onClick: () => void; className?: string; 'aria-label'?: string; 'data-id'?: string }) {
  return <button type="button" className={className} data-action={action} onClick={onClick} {...rest}>{children}</button>;
}
function Field({ label, name, ...props }: InputHTMLAttributes<HTMLInputElement> & { label: string; name: string }) {
  return <label className="field">{label}<input name={name} {...props} /></label>;
}
function Form({ kind, run, onSubmit, children }: { kind: string; run: Run; onSubmit: (values: Record<string, string>) => void; children: ReactNode }) {
  return <form data-form={kind} onSubmit={(event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const values = Object.fromEntries(new FormData(event.currentTarget)) as Record<string, string>; run(() => onSubmit(values));
  }}>{children}</form>;
}
const mobileProps = { type: 'tel', required: true, pattern: '09[0-9]{9}', maxLength: 11 } as const;
const pinProps = { type: 'password', required: true, pattern: '[0-9]{4}', maxLength: 4, inputMode: 'numeric' } as const;

function Transactions({ d, limit = 99 }: { d: Device; limit?: number }) {
  const u = currentUser(d)!;
  const rows = d.ledger.filter(t => t.sender === u.mobile || (t.receiver === u.mobile && d.receipts.includes(t.tx_id))).slice().reverse().slice(0, limit);
  if (!rows.length) return <div className="empty">Your first payment starts here.<br />Send or receive to see it in your history.</div>;
  return <>{rows.map(t => { const sent = t.sender === u.mobile; return <div className="tx" key={t.tx_id}>
    <Button action="open-tx" className="" data-id={t.tx_id} aria-label="Open transaction" onClick={() => wallet.openTransaction(d.key, t.tx_id)}>
      <div className="row"><span className="value">{sent ? '−' : '+'}{money(t.cents)}</span><span>{sent ? '↗' : '↙'}</span></div>
      <div className="who">{sent ? 'To ' + t.receiver : 'From ' + t.sender} · {new Date(t.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
      <span className={`state ${t.status === 'SYNCED' ? 'synced' : ''}`}>{t.status}</span>
    </Button></div>; })}</>;
}
function AuthScreen({ d, run }: { d: Device; run: Run }) {
  return <><div className="demo-badge">LOCAL DEMO · NO REAL MONEY</div><h2 style={{ marginTop: 24 }}>Your wallet.<br />Even offline.</h2><p>Create an account, or use the demo to try both phones.</p>
    <div className="tabs"><Button action="login-tab" className={d.mode === 'login' ? 'selected' : ''} onClick={() => wallet.mode(d.key, 'login')}>Log in</Button><Button action="register-tab" className={d.mode === 'register' ? 'selected' : ''} onClick={() => wallet.mode(d.key, 'register')}>Register</Button></div>
    <Form kind="auth" run={run} onSubmit={v => wallet.auth(d.key, v, d.mode === 'register')}>
      {d.mode === 'register' && <Field label="Full name" name="name" required minLength={2} maxLength={80} />}
      <Field label="Mobile number" name="mobile" {...mobileProps} placeholder="09XXXXXXXXX" />
      <Field label="4-digit wallet PIN" name="pin" {...pinProps} />
      <button className="primary">{d.mode === 'register' ? 'Create account' : 'Open wallet'}</button>
    </Form><Button action="local-demo" className="outline" onClick={() => run(() => wallet.setupLocal(d.key))}>Quick Demo Setup</Button>
    <p style={{ fontSize: 10 }}>Person 1: 09171111111 · Person 2: 09172222222<br />Both PINs: 1234</p></>;
}
function HomeScreen({ d, run }: { d: Device; run: Run }) {
  const u = currentUser(d)!;
  return <><div className="demo-badge">OFFLINE · DEMO WALLET</div><h2>Hello, {u.name}</h2><div className="sub">{u.mobile}</div>
    <div className="balance"><small>AVAILABLE DEMO BALANCE</small><b data-balance={d.key}>{money(u.balance)}</b><span>Local to this demo phone</span></div>
    <div className="actions"><button className="action" data-action="cashin" onClick={() => wallet.modal(d.key, 'cashin')}><i>＋</i>Add money</button><button className="action" data-action="send" onClick={() => wallet.navigate(d.key, 'send')}><i>↗</i>Send</button><button className="action" data-action="receive" onClick={() => wallet.navigate(d.key, 'receive')}><i>↙</i>Receive</button></div>
    <Button action="sync" className="outline" onClick={() => run(() => wallet.sync(d.key))}>↻ Simulate reconnect &amp; sync</Button><div className="row"><h3>Recent activity</h3><Button action="history" className="iconbtn" onClick={() => wallet.navigate(d.key, 'history')}>View all →</Button></div><Transactions d={d} limit={4} /><p style={{ fontSize: 10 }}>No network or real money. Balances belong to this browser session.</p></>;
}
function SendScreen({ d, state, run }: { d: Device; state: WalletState; run: Run }) {
  const other = currentUser(state.devices[d.key === 'A' ? 'B' : 'A']);
  return <><h2>Send without data.</h2><p>The recipient must use the number below. Your balance changes only after approval.</p>
    <Form kind="send" run={run} onSubmit={v => wallet.prepare(d.key, v.receiver.trim(), v.amount)}>
      <Field label="Receiver mobile number" name="receiver" defaultValue={d.draft.receiver || other?.mobile || ''} {...mobileProps} />
      <Field label="Amount in pesos" name="amount" defaultValue={d.draft.amount} required inputMode="decimal" placeholder="25.00" />
      <p>Available: <strong>{money(currentUser(d)!.balance)}</strong></p><button className="primary">Authorize payment →</button>
    </Form><div className="note">Confirm your wallet PIN, then approve a simulated device-authentication prompt. Browser biometrics are simulated.</div></>;
}
function QR({ payment }: { payment: Payment }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => { const ctx = ref.current?.getContext('2d'); if (!ctx) return;
    ctx.fillStyle = 'white'; ctx.fillRect(0, 0, 175, 175); ctx.fillStyle = '#153f32';
    for (let y = 0; y < 25; y++) for (let x = 0; x < 25; x++) {
      let on = false, found = false;
      for (const [fx, fy] of [[0, 0], [18, 0], [0, 18]]) if (x >= fx && x < fx + 7 && y >= fy && y < fy + 7) { const a = x - fx, b = y - fy; on = a === 0 || a === 6 || b === 0 || b === 6 || (a >= 2 && a <= 4 && b >= 2 && b <= 4); found = true; break; }
      if (!found) on = (parseInt(payment.signature_token[(x + y * 25) % 64], 16) + x + y) % 3 === 0;
      if (on) ctx.fillRect(x * 7, y * 7, 7, 7);
    }
  }, [payment.signature_token]);
  return <canvas ref={ref} className="qr" width={175} height={175} aria-label="Illustrative payment QR; use the simulated scan button" />;
}
function PaymentScreen({ d, run }: { d: Device; run: Run }) {
  const t = d.outgoing!; const textarea = useRef<HTMLTextAreaElement>(null);
  async function copy() { try { await navigator.clipboard.writeText(payload(t)); wallet.notify(d.key, 'Signed token copied.'); } catch { textarea.current?.select(); wallet.notify(d.key, 'Select and copy the token manually.'); } }
  return <><div className="receipt"><div className="demo-badge">DEBITED ONCE · READY TO DELIVER</div><div className="amount">{money(t.cents)}</div><p>To {t.receiver}</p></div><QR payment={t} /><p style={{ textAlign: 'center', fontSize: 10 }}>Illustrative QR · use the simulation below</p>
    <Button action="qr" onClick={() => run(() => wallet.deliver(d.key, 'QR'))}>▦ Simulate receiver scanning QR</Button><Button action="nfc" className="secondary" onClick={() => run(() => wallet.deliver(d.key, 'NFC'))}>⌁ Simulate NFC tap to other phone</Button>
    <div className="note">Deliver this signed token to the other demo phone. These buttons never debit again. No camera or NFC radio is used.</div>
    <details><summary>Inspect or copy the signed payload</summary><label className="field">Browser-demo token<textarea ref={textarea} readOnly data-outgoing value={payload(t)} /></label><Button action="copy" className="outline" onClick={() => run(copy)}>Copy payload</Button></details><Button action="home" className="outline" onClick={() => wallet.navigate(d.key, 'home')}>Back to wallet</Button></>;
}
function ReceiveScreen({ d, run }: { d: Device; run: Run }) {
  const t = d.incoming, u = currentUser(d)!;
  return <><h2>Ready to receive.</h2><div className="sub">{u.name} · {u.mobile}</div><div className="note">On the other phone, open a payment and choose simulated QR or NFC delivery. Or paste a browser-demo token below.</div>
    {t ? <div className="request"><div className="demo-badge">{t.transport} · DELIVERED</div><p>From {t.sender}</p><strong>{money(t.cents)}</strong><p>To {t.receiver}</p><Button action="accept" onClick={() => run(() => wallet.accept(d.key))}>Validate &amp; receive payment</Button></div> : <div className="empty">Waiting for a payment token…<br />Both phone panels are live.</div>}
    <Form kind="paste" run={run} onSubmit={v => wallet.accept(d.key, v.payload.trim())}><label className="field">Paste signed browser-demo JSON<textarea name="payload" required placeholder="Paste the sender’s demo token" /></label><button className="outline">Validate pasted payment</button></Form></>;
}
function ReceiptScreen({ d }: { d: Device }) {
  const t = d.received!, status = d.ledger.find(row => row.tx_id === t.tx_id)?.status || 'OFFLINE_PENDING';
  return <><div className="receipt"><div className="success">✓</div><h2>Payment received</h2><div className="amount">{money(t.cents)}</div><p>From {t.sender}</p><span className={`state ${status === 'SYNCED' ? 'synced' : ''}`}>{status}</span></div><div style={{ marginTop: 25 }}>{['Correct recipient', 'HMAC signature verified', 'New transaction ID', 'Wallet credited once'].map(s => <div className="checkline" key={s}><span>✓</span>{s}</div>)}</div><p style={{ fontSize: 13, marginTop: 22 }}>New balance: <strong>{money(currentUser(d)!.balance)}</strong></p><Button action="home" onClick={() => wallet.navigate(d.key, 'home')}>Done · open wallet</Button><div className="note">Deliver this same payment again. A local replay check blocks a second credit.</div></>;
}
function Modal({ d, run }: { d: Device; run: Run }) {
  const ref = useRef<HTMLElement>(null), m = d.modal!;
  useEffect(() => { const el = ref.current; el?.querySelector<HTMLElement>('[autofocus], input, button')?.focus({ preventScroll: true }); }, [m.type]);
  return <div className="overlay"><section ref={ref} className="modal" role="dialog" aria-modal="true" aria-label={m.type === 'cashin' ? 'Add mock funds' : m.type === 'switch' ? 'Switch account' : 'Authorize payment'} onKeyDown={e => {
    if (e.key === 'Escape') { wallet.cancel(d.key); return; }
    if (e.key !== 'Tab') return; const nodes = [...e.currentTarget.querySelectorAll<HTMLElement>('button, input, textarea')]; const first = nodes[0], last = nodes.at(-1);
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); } else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); }
  }}>
    {m.type === 'cashin' && <><h3>Add mock funds</h3><p>Only this account gets the added demo money.</p><Form kind="cashin" run={run} onSubmit={v => wallet.cashIn(d.key, v.amount)}><Field label="Amount in pesos" name="amount" required inputMode="decimal" placeholder="100.00" autoFocus /><button className="primary">Add money</button></Form></>}
    {m.type === 'pin' && <><h3>Authorize {money(m.cents)}</h3><p>To {m.receiver}. Enter this account’s wallet PIN.</p><Form kind="pin" run={run} onSubmit={v => wallet.verifyPin(d.key, v.pin)}><Field label="Wallet PIN" name="pin" {...pinProps} autoFocus /><button className="primary">Continue</button></Form></>}
    {m.type === 'device' && <><h3>Verify your identity</h3><div className="device-check"><span>◎</span>Fingerprint / device passcode</div><p>This is a <strong>simulated</strong> prompt. The Flutter app uses local_auth for real device authentication.</p><Button action="approve" onClick={() => run(() => wallet.approve(d.key))}>Simulate successful verification</Button><p>Approve {money(m.cents)} to {m.receiver}. Only this approval debits the wallet.</p></>}
    {m.type === 'switch' && <><h3>Switch account</h3><p>Log in to another account on this phone. Demo PIN: 1234.</p><Form kind="switch" run={run} onSubmit={v => wallet.auth(d.key, v)}><Field label="Mobile number" name="mobile" defaultValue={currentUser(d)?.mobile === '09171111111' ? '09172222222' : '09171111111'} {...mobileProps} autoFocus /><Field label="Wallet PIN" name="pin" {...pinProps} /><button className="primary">Switch wallet</button></Form></>}
    <Button action="cancel" className="secondary" onClick={() => { wallet.cancel(d.key); wallet.notify(d.key, 'Cancelled. No funds deducted.'); }}>Cancel</Button>
  </section></div>;
}
function Toast({ d }: { d: Device }) {
  const toast = d.toast!;
  useEffect(() => { const timer = setTimeout(() => wallet.dismiss(d.key, toast.id), 6500); return () => clearTimeout(timer); }, [d.key, toast.id]);
  return <div className={`toast ${toast.error ? 'error' : ''}`} role="status">{toast.text}</div>;
}
function Phone({ d, state }: { d: Device; state: WalletState }) {
  const run: Run = work => { try { Promise.resolve(work()).catch(e => wallet.notify(d.key, e instanceof Error ? e.message : 'Operation failed.', true)); } catch (e) { wallet.notify(d.key, e instanceof Error ? e.message : 'Operation failed.', true); } };
  let content: ReactNode;
  switch (d.screen) {
    case 'auth': content = <AuthScreen d={d} run={run} />; break;
    case 'home': content = <HomeScreen d={d} run={run} />; break;
    case 'send': content = <SendScreen d={d} state={state} run={run} />; break;
    case 'payment': content = <PaymentScreen d={d} run={run} />; break;
    case 'receive': content = <ReceiveScreen d={d} run={run} />; break;
    case 'receipt': content = <ReceiptScreen d={d} />; break;
    case 'history': content = <><h2>Every transfer, here.</h2><p>Payments sent or received by this account. Cash-in is mock funding.</p><Button action="sync" className="outline" onClick={() => run(() => wallet.sync(d.key))}>↻ Simulate reconnect &amp; sync</Button><Transactions d={d} /></>; break;
  }
  return <article className={`device ${state.activeTab !== d.key ? 'hidden-mobile' : ''}`} data-device={d.key}><div className="device-label"><span>PHONE {d.key} · {d.key === 'A' ? 'SENDER' : 'RECEIVER'}</span><small>● Local sandbox</small></div><div className="phone" data-phone={d.key}>
    <div className="status"><span>9:41</span><span>OFFLINE ▮</span></div><div className="notch" /><div className="appbar" inert={!!d.modal}>{!['auth', 'home'].includes(d.screen) && <Button action="home" className="iconbtn" aria-label="Back to wallet" onClick={() => wallet.navigate(d.key, 'home')}>←</Button>}<strong>{titles[d.screen]}</strong>{currentUser(d) ? <Button action="switch" className="iconbtn" onClick={() => wallet.modal(d.key, 'switch')}>Switch</Button> : <span />}</div>
    <div className="screen" inert={!!d.modal}>{content}</div><div className="bottom" />{d.modal && <Modal d={d} run={run} />}{d.toast && <Toast d={d} />}
  </div></article>;
}
function speak(text: string) { if (!('speechSynthesis' in window)) return; speechSynthesis.cancel(); const utterance = new SpeechSynthesisUtterance(text); utterance.lang = 'en-US'; utterance.rate = .96; const voices = speechSynthesis.getVoices(); utterance.voice = voices.find(v => v.lang === 'en-US' && /Zira|Natural|Samantha/.test(v.name)) || voices.find(v => v.lang === 'en-US') || null; speechSynthesis.speak(utterance); }

export default function App() {
  const state = useSyncExternalStore(wallet.subscribe, wallet.getSnapshot);
  const [voice, setVoice] = useState(false), [videoError, setVideoError] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null), video = useRef<HTMLVideoElement>(null), watch = useRef<HTMLButtonElement>(null);
  const next = steps.findIndex((_, i) => !state.completed.includes(i));
  useEffect(() => { if (voice) speak(next < 0 ? 'You finished the flow. Try another payment.' : steps[next][1]); }, [voice, next]);
  useEffect(() => () => { if ('speechSynthesis' in window) speechSynthesis.cancel(); }, []);
  useEffect(() => {
    // QA exposes only snapshots/pure functions, never a wallet mutation hook.
    window.TapDemo = { snapshot: () => structuredClone(wallet.getSnapshot()), sha: shaText, hmac, parse, amount };
    return () => { delete window.TapDemo; };
  }, []);
  function reset() { wallet.reset(); if ('speechSynthesis' in window) speechSynthesis.cancel(); }
  function closeVideo() { video.current?.pause(); watch.current?.focus(); }
  return <><header><div className="brand">TapC<span>Peso</span></div><span className="badge">OFFLINE WALLET · INTERACTIVE SANDBOX</span><div className="tools">
    <button ref={watch} className="secondary" id="watch-demo" onClick={() => { setVoice(false); if ('speechSynthesis' in window) speechSynthesis.cancel(); dialog.current?.showModal(); if (video.current) { video.current.currentTime = 0; void video.current.play().catch(() => {}); } }}>▶ <span className="watch-label">Watch 1-min demo</span><span className="watch-short">Demo</span></button>
    <button className="secondary" id="voice" aria-pressed={voice} onClick={() => { if ('speechSynthesis' in window) { if (voice) speechSynthesis.cancel(); setVoice(!voice); } }}>Voice guide: {voice ? 'on' : 'off'}</button><button className="secondary" id="reset" onClick={reset}>↻ <span className="reset-label">Reset demo</span></button>
  </div></header><main className="layout"><aside className="sidebar"><div className="eyebrow">TRY IT. TAP BY TAP.</div><h1>Offline money.<br /><em>You're in control.</em></h1><p className="intro">Two phones. One payment. Tap through the flow, change the amount, and see both balances respond.</p><button className="primary" id="start" onClick={() => wallet.setupBoth()}>{state.completed.includes(0) ? 'Open both demo wallets →' : 'Set up both demo wallets →'}</button>
    <div className="guide"><div className="guide-head"><span>Your first transfer</span><span id="count">{state.completed.length} / 6</span></div><ol className="steps" id="steps">{steps.map((s, i) => <li key={s[0]} className={state.completed.includes(i) ? 'done' : i === next ? 'current' : ''}><span className="number">{state.completed.includes(i) ? '✓' : i + 1}</span><span>{s[0]}</span></li>)}</ol><div className="hint" id="hint" aria-live="polite"><strong>{next < 0 ? 'You did it.' : steps[next][0]}</strong>{next < 0 ? 'Try a new amount, another account, or an altered payload.' : steps[next][1]}</div></div>
    <div className="legend">Demo PINs: <strong>1234</strong><br />Person 1: 09171111111<br />Person 2: 09172222222<details><summary>What is simulated?</summary><p>This browser sandbox uses session memory and demo HMAC tokens. NFC, QR delivery and device authentication are simulated. It never connects to your Flutter SQLite wallets, camera, or NFC radio.</p></details></div>
  </aside><section aria-label="Interactive wallet devices"><div className="mobile-tabs">{(['A', 'B'] as const).map(k => <button key={k} data-tab={k} className={state.activeTab === k ? 'active' : ''} onClick={() => wallet.tab(k)}>Phone {k} · {k === 'A' ? 'Sender' : 'Receiver'}</button>)}</div><div className="phones" id="phones">{(['A', 'B'] as const).map(k => <Phone key={k} d={state.devices[k]} state={state} />)}</div></section></main>
  <footer><div>Interactive browser preview · Demo money only · Reloading resets the session.<br />The Flutter application uses SQLite. This preview is a separate sandbox.</div><div>Native NFC: Android sender → compatible Android/iPhone reader.<br />iPhone sends by QR. Physical NFC remains unverified.</div></footer>
  <dialog ref={dialog} id="demo-dialog" aria-labelledby="video-title" onClose={closeVideo} onClick={e => { if (e.target === e.currentTarget) { const bounds = e.currentTarget.getBoundingClientRect(); if (e.clientX < bounds.left || e.clientX > bounds.right || e.clientY < bounds.top || e.clientY > bounds.bottom) e.currentTarget.close(); } }}>
    <div className="video-top"><div><h2 id="video-title">How TapCPeso works</h2><p>{videoError ? 'The demo video could not load. Check your connection and try again.' : 'A narrated, animated app walkthrough · 1 minute'}</p></div><button className="video-close" id="video-close" aria-label="Close demo video" onClick={() => dialog.current?.close()}>×</button></div>
    <video ref={video} id="walkthrough-video" controls playsInline preload="metadata" src={videoUrl} onError={() => setVideoError(true)} aria-label="TapCPeso animated wallet walkthrough" />
    <div className="video-foot"><span>TapCPeso UI preview · synthetic narration · QR/NFC and authentication shown as simulations.</span><a href={videoUrl} download>Download the MP4 ↗</a></div>
  </dialog></>;
}

declare global {
  interface Window { TapDemo?: { snapshot: () => WalletState; sha: typeof shaText; hmac: typeof hmac; parse: typeof parse; amount: typeof amount } }
}
