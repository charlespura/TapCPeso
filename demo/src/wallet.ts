import type { Device, DeviceId, Payment, Screen, User, WalletState } from './types';
import { amount, hashPin, hmac, uid } from './crypto';

export const money = (c: number) => 'PHP ' + (c / 100).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const validMobile = (v: unknown): v is string => typeof v === 'string' && /^09[0-9]{9}$/.test(v);
export const currentUser = (d: Device) => d.users.find(u => u.mobile === d.current);
export const steps = [
  ['Set up two wallets', 'Tap “Set up both demo wallets”. Person 1 opens on phone A and Person 2 on phone B. Each starts with PHP 1,000.'],
  ['Add some mock money', 'On phone A, tap Add money and add an amount. Only that wallet changes.'],
  ['Authorize a payment', 'On phone A, tap Send. Enter phone B’s number and an amount. Use PIN 1234, then approve the simulated device check.'],
  ['Receive on phone B', 'Deliver the token using the simulated QR or NFC button. On phone B, review and accept it.'],
  ['Try the same payment again', 'Deliver the original payment again from phone A. Phone B will reject the replay without changing its balance.'],
  ['Review and sync', 'Tap Sync on both phones. Valid local records become SYNCED, and balances stay the same.'],
] as const;
export const titles: Record<Screen, string> = { auth: 'TapCPeso', home: 'TapCPeso', send: 'Send offline', payment: 'Payment ready', receive: 'Receive offline', receipt: 'Payment received', history: 'History' };
const newDevice = (key: DeviceId): Device => ({ key, users: [], current: null, screen: 'auth', mode: 'login', ledger: [], receipts: [], outgoing: null, incoming: null, received: null, modal: null, toast: null, draft: { receiver: '', amount: '' } });
const initial = (): WalletState => ({ devices: { A: newDevice('A'), B: newDevice('B') }, completed: [], activeTab: 'A' });
export const canonical = (t: Payment) => JSON.stringify({ demo_version: 1, tx_id: t.tx_id, sender: t.sender, receiver: t.receiver, cents: t.cents, timestamp: t.timestamp });
export const payload = (t: Payment) => JSON.stringify({ ...JSON.parse(canonical(t)), signature_token: t.signature_token });
export function parse(text: string): Payment {
  let t: unknown;
  try { t = JSON.parse(text); } catch { throw Error('Invalid JSON. Paste a complete demo token.'); }
  if (!t || typeof t !== 'object' || Array.isArray(t)) throw Error('Invalid browser-demo token.');
  const p = t as Record<string, unknown>;
  if (Object.keys(p).length !== 7 || p.demo_version !== 1 || typeof p.tx_id !== 'string' || !/^demo-[0-9a-f]{32}$/.test(p.tx_id) ||
    !validMobile(p.sender) || !validMobile(p.receiver) || p.sender === p.receiver || typeof p.cents !== 'number' || !Number.isInteger(p.cents) || p.cents <= 0 || p.cents > 100000000 ||
    typeof p.timestamp !== 'string' || !Number.isFinite(Date.parse(p.timestamp)) || Date.parse(p.timestamp) > Date.now() + 300000 || typeof p.signature_token !== 'string') {
    throw Error('Invalid browser-demo token. Native wallet tokens are not accepted here.');
  }
  const payment = p as unknown as Payment;
  if (hmac(canonical(payment)) !== payment.signature_token) throw Error('Signature invalid: payload changed. No funds credited.');
  return payment;
}
function account(d: Device): User { const u = currentUser(d); if (!u) throw Error('Log in first.'); return u; }
function create(d: Device, name: string, mobile: string, pin: string, balance = 0) {
  if (d.users.some(u => u.mobile === mobile)) throw Error('That number is already registered on this phone.');
  const salt = uid(); d.users.push({ name, mobile, salt, pinHash: hashPin(pin, salt), balance });
}
function setup(d: Device) {
  for (const [name, number] of [['Person 1', '09171111111'], ['Person 2', '09172222222']]) {
    if (!d.users.some(u => u.mobile === number)) create(d, name, number, '1234', 100000);
  }
}
function finish(s: WalletState, n: number) { if (!s.completed.includes(n)) s.completed.push(n); }
function login(d: Device, mobile: string, pin: string) {
  const u = d.users.find(u => u.mobile === mobile);
  if (!u || hashPin(pin, u.salt) !== u.pinHash) throw Error('Incorrect mobile number or wallet PIN.');
  d.current = u.mobile; d.screen = 'home'; d.modal = null; d.incoming = null;
}
let state = initial();
const listeners = new Set<() => void>();
let toastId = 0;
const update = (fn: (next: WalletState) => void) => { const next = structuredClone(state); fn(next); state = next; listeners.forEach(fn => fn()); };
export const wallet = {
  subscribe(fn: () => void) { listeners.add(fn); return () => { listeners.delete(fn); }; },
  getSnapshot: () => state,
  reset() { state = initial(); listeners.forEach(fn => fn()); },
  tab(key: DeviceId) { update(s => { s.activeTab = key; }); },
  notify(key: DeviceId, text: string, error = false) { update(s => { s.devices[key].toast = { text, error, id: ++toastId }; }); },
  dismiss(key: DeviceId, id: number) { if (state.devices[key].toast?.id === id) update(s => { s.devices[key].toast = null; }); },
  setupBoth() { update(s => { for (const d of Object.values(s.devices)) { setup(d); d.current = d.key === 'A' ? '09171111111' : '09172222222'; d.screen = 'home'; d.modal = null; } finish(s, 0); s.activeTab = 'A'; }); },
  setupLocal(key: DeviceId) { update(s => { const d = s.devices[key]; setup(d); d.current = key === 'A' ? '09171111111' : '09172222222'; d.screen = 'home'; if (currentUser(s.devices.A) && currentUser(s.devices.B)) finish(s, 0); }); },
  mode(key: DeviceId, mode: 'login' | 'register') { update(s => { s.devices[key].mode = mode; }); },
  navigate(key: DeviceId, screen: Screen) { update(s => { const d = s.devices[key]; d.screen = screen; d.modal = null; if (screen === 'send') d.draft = { receiver: '', amount: '' }; }); },
  modal(key: DeviceId, type: 'cashin' | 'switch') { update(s => { s.devices[key].modal = { type }; }); },
  cancel(key: DeviceId) { update(s => { s.devices[key].modal = null; }); },
  auth(key: DeviceId, values: Record<string, string>, register = false) {
    update(s => { const d = s.devices[key]; if (register) {
      if (!values.name || values.name.trim().length < 2 || values.name.trim().length > 80 || !validMobile(values.mobile) || !/^\d{4}$/.test(values.pin)) throw Error('Enter a name, 09 mobile number, and 4-digit PIN.');
      create(d, values.name.trim(), values.mobile, values.pin);
    } login(d, values.mobile, values.pin); if (currentUser(s.devices.A) && currentUser(s.devices.B)) finish(s, 0); });
  },
  cashIn(key: DeviceId, value: string) { const n = amount(value); update(s => { const u = account(s.devices[key]); if (u.balance + n > 100000000) throw Error('Demo wallet limit is PHP 1,000,000.'); u.balance += n; s.devices[key].modal = null; finish(s, 1); }); this.notify(key, money(n) + ' in mock funds added.'); },
  prepare(key: DeviceId, receiver: string, value: string) { const n = amount(value); update(s => { const d = s.devices[key], u = account(d); if (!validMobile(receiver)) throw Error('Enter an 11-digit 09 mobile number.'); if (receiver === u.mobile) throw Error('Choose a different receiver.'); if (n > u.balance) throw Error('Insufficient balance. Add mock funds first.'); d.draft = { receiver, amount: value }; d.modal = { type: 'pin', receiver, cents: n }; }); },
  verifyPin(key: DeviceId, pin: string) { update(s => { const d = s.devices[key], u = account(d); if (d.modal?.type !== 'pin') return; if (hashPin(pin, u.salt) !== u.pinHash) throw Error('Incorrect PIN. No funds deducted.'); d.modal = { ...d.modal, type: 'device' }; }); },
  approve(key: DeviceId) { update(s => { const d = s.devices[key], u = account(d), m = d.modal; if (m?.type !== 'device') return; if (u.balance < m.cents) throw Error('Insufficient balance.'); const t: Payment = { demo_version: 1, tx_id: 'demo-' + uid(), sender: u.mobile, receiver: m.receiver, cents: m.cents, timestamp: new Date().toISOString(), signature_token: '' }; t.signature_token = hmac(canonical(t)); u.balance -= t.cents; d.ledger.push({ ...t, status: 'OFFLINE_PENDING' }); d.outgoing = t; d.screen = 'payment'; d.modal = null; finish(s, 2); }); },
  deliver(key: DeviceId, transport: 'QR' | 'NFC') { const otherKey = key === 'A' ? 'B' : 'A'; update(s => { const t = s.devices[key].outgoing, other = s.devices[otherKey]; if (!t) throw Error('Create or open a payment first.'); account(other); other.incoming = { ...t, transport }; other.screen = 'receive'; other.modal = null; s.activeTab = otherKey; }); this.notify(key, `${transport} simulation delivered the token. Receive it on phone ${otherKey}.`); },
  accept(key: DeviceId, text?: string) {
    const d = state.devices[key]; const t = parse(text ?? (d.incoming ? payload(d.incoming) : ''));
    const u = account(d); if (t.receiver !== u.mobile) throw Error('Wrong recipient. Addressed to ' + t.receiver + '.');
    if (d.receipts.includes(t.tx_id)) { update(s => finish(s, 4)); throw Error('Duplicate payment rejected. Already received; balance unchanged.'); }
    update(s => { const target = s.devices[key], receiver = account(target); if (receiver.balance + t.cents > 100000000) throw Error('This would exceed the PHP 1,000,000 wallet limit.'); const existing = target.ledger.find(row => row.tx_id === t.tx_id); if (existing && payload(existing) !== payload(t)) throw Error('Transaction ID conflicts with an existing record.'); if (!existing) target.ledger.push({ ...t, status: 'OFFLINE_PENDING' }); else existing.status = 'OFFLINE_PENDING'; target.receipts.push(t.tx_id); receiver.balance += t.cents; target.received = t; target.incoming = null; target.screen = 'receipt'; finish(s, 3); });
  },
  sync(key: DeviceId) { let valid = 0, invalid = 0; update(s => { s.devices[key].ledger.forEach(t => { if (t.status === 'OFFLINE_PENDING') { try { parse(payload(t)); t.status = 'SYNCED'; valid++; } catch { invalid++; } } }); if (s.devices.A.ledger.some(t => t.status === 'SYNCED') && s.devices.B.ledger.some(t => t.status === 'SYNCED')) finish(s, 5); }); this.notify(key, `${valid} verified and synced; ${invalid} invalid left pending. Balance unchanged; no network used.`); },
  openTransaction(key: DeviceId, id: string) { update(s => { const d = s.devices[key], t = d.ledger.find(t => t.tx_id === id); if (!t) return; if (t.sender === account(d).mobile) { d.outgoing = t; d.screen = 'payment'; } else { d.received = t; d.screen = 'receipt'; } }); },
};
