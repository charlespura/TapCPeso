export type DeviceId = 'A' | 'B';
export type Screen = 'auth' | 'home' | 'send' | 'payment' | 'receive' | 'receipt' | 'history';
export interface User {
  name: string; mobile: string; salt: string; pinHash: string; balance: number;
}
export interface Payment {
  demo_version: 1; tx_id: string; sender: string; receiver: string; cents: number;
  timestamp: string; signature_token: string;
}
export interface Transaction extends Payment { status: 'OFFLINE_PENDING' | 'SYNCED' }
export type Modal = { type: 'cashin' | 'switch' } |
  { type: 'pin' | 'device'; receiver: string; cents: number };
export interface Device {
  key: DeviceId; users: User[]; current: string | null; screen: Screen;
  mode: 'login' | 'register'; ledger: Transaction[]; receipts: string[];
  outgoing: Payment | null; incoming: (Payment & { transport: 'QR' | 'NFC' }) | null;
  received: Payment | null; modal: Modal | null;
  toast: { text: string; error: boolean; id: number } | null;
  draft: { receiver: string; amount: string };
}
export interface WalletState {
  devices: Record<DeviceId, Device>; completed: number[]; activeTab: DeviceId;
}
