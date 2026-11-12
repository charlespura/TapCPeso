# TapCPeso

The [React + TypeScript demo](demo/README.md) includes two working wallet panels,
editable amounts, simulated QR/NFC transfers, replay rejection, sync, an optional
voice guide, and a [one-minute video](demo/tapcpeso-demo.mp4). Run it with
`cd demo`, `npm ci`, then `npm run dev`. It remains separate from the native
SQLite app. A [GitHub Pages workflow](.github/workflows/deploy.yml) builds and
deploys the React demo when demo changes are pushed to `main`.

A native Flutter Android/iOS offline wallet prototype. SQLite (`sqflite`) is the
only persistent store. There is no backend, Firebase, network sync, or real money.
Material 3 UI, local registration/login, cash-in, device authentication, signed
payments, QR transfer, real NFC where supported, mock NFC, history and local sync
are implemented in `lib/`.

## First run

Install **latest stable Flutter** (3.41 or newer), its Android tooling, and Python
3. On macOS install Xcode for iOS. This repository includes application source and
native overrides; generate the SDK-owned Gradle wrapper, Xcode project, launch
assets and platform scaffolding once:

```sh
python tool/bootstrap.py
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

On macOS use `python3` if `python` is unavailable. Windows can also run
`powershell -ExecutionPolicy Bypass -File tool/bootstrap.ps1`.
Bootstrap preserves committed Kotlin, Swift, XML and entitlements and leaves
`lib/`, `test/` and `pubspec.yaml` unchanged. If interrupted, rename
`.dart_tool/platform_scaffold` before retrying. Initial dependency/build downloads
need internet; installed app transfers work in airplane mode with NFC re-enabled.

For iOS, open `ios/Runner.xcworkspace` in Xcode on a **Mac**, select your signing
team and unique bundle identifier, and enable **Near Field Communication Tag
Reading** under Signing & Capabilities. The supplied entitlements file and
bootstrap configure the `TAG` entitlement, ISO7816 AID, NFC usage text, camera and
Face ID permissions. NFC requires a supported physical iPhone and matching
provisioning profile. A simulator can use mock NFC; physical camera scanning
needs a camera. Android requires API 24+, a configured screen lock, and optional
NFC/HCE hardware. iOS cannot be compiled on this Windows workspace.

## Two-device transport support

| Sender → receiver | QR | Real NFC in this prototype |
| --- | --- | --- |
| Android → Android | Yes | Android sender needs HCE; receiver needs ISO-DEP NFC reader |
| Android → iPhone | Yes | iPhone uses Core NFC ISO7816 reader, with NFC signing capability |
| iPhone → Android | Yes | Unavailable: use QR |
| iPhone → iPhone | Yes | Unavailable: use QR |

Android uses native `HostApduService` and reader mode, not deprecated Android
Beam. iOS uses native `NFCTagReaderSession`. iPhone card emulation is subject to
Apple-managed eligibility and entitlements; this project does not pretend a tag
reader permission enables unrestricted iPhone sending. See
[Apple CardSession](https://developer.apple.com/documentation/CoreNFC/CardSession)
and [Android HCE](https://developer.android.com/develop/connectivity/nfc/hce).

**Real NFC and mock NFC are separate controls.** Mock NFC never transmits by radio.
It loads an unreceived local transaction on a shared device or accepts pasted JSON.
Real NFC transports that same signed JSON using a custom ISO7816 APDU protocol.
All receive paths go through `DBHelper.receive()` and the same validation.

## Test with two physical devices

1. Install the app on both phones. Tap **Quick Demo Setup** on each. Log in as
   Person 1 (`09171111111`) on phone A and Person 2 (`09172222222`) on phone B.
   Both wallet PINs are `1234`; each new local account starts with PHP 1,000.
   Repeating setup never refills or replaces existing accounts.
2. Set screen-lock PIN / biometrics on the sender. Disable Wi-Fi/mobile data;
   re-enable NFC if airplane mode turned it off. Leave both phones unlocked.
3. Phone A: **Send offline**, receiver `09172222222`, amount `25.00`.
   Enter wallet PIN, then complete biometric/device-PIN authentication.
   Phone A now has PHP 975.00. Do not create another payment to retry delivery.
4. For QR: phone B selects **Receive offline**, turns off Mock NFC mode and scans
   phone A's QR. For real NFC: phone A must be Android; press **Start real NFC
   tap**, then phone B presses **Receive via real NFC**. Hold the phones' NFC
   antenna areas together for the whole read (iPhone usually top edge; Android
   antenna position varies). Open NFC settings if the app reports NFC disabled.
5. Wait for **Payment received** on phone B. Its Person 2 balance becomes PHP
   1,025.00. Both device ledgers show `OFFLINE_PENDING`. The sender does not get a
   wallet-credit acknowledgement; the receiver's success screen is confirmation.
6. Try the **same** QR/NFC payment again. The receiver must report a duplicate,
   keep PHP 1,025.00, and create no second transaction. A dropped NFC read can be
   retried using the original payment from history, including by QR.
7. On each device choose **Simulate reconnect & sync**. Valid local records become
   `SYNCED`; balances do not change. Devices sync independently; no messages are
   exchanged. Test a wrong receiver account and altered JSON: neither credits.
8. Restart both apps, log back in, and confirm balances and history persist.

For one-device testing, send as Person 1, switch to Person 2, open Receive → Mock
NFC and select the waiting transaction. A receipt table allows the sender and
receiver to share a transaction row while crediting it once.

## Dependencies and native configuration

The exact dependency declarations are in [pubspec.yaml](pubspec.yaml):

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.4.6
  path: ^1.9.1
  local_auth: ^3.0.2
  crypto: ^3.0.8
  qr_flutter: ^4.1.0
  mobile_scanner: ^7.5.0
dev_dependencies:
  flutter_test:
    sdk: flutter
  sqflite_common_ffi: ^2.4.7
```

`sqflite_common_ffi` is test-only SQLite, not a second persistence system. Run
`flutter pub get` and retain the generated `pubspec.lock` for reproducible builds.
Package versions were checked against official pub.dev pages:
[sqflite](https://pub.dev/packages/sqflite),
[local_auth](https://pub.dev/packages/local_auth),
[mobile_scanner](https://pub.dev/packages/mobile_scanner),
[crypto](https://pub.dev/packages/crypto),
[qr_flutter](https://pub.dev/packages/qr_flutter),
[path](https://pub.dev/packages/path).

Android's [manifest](android/app/src/main/AndroidManifest.xml) declares CAMERA,
USE_BIOMETRIC and NFC permissions, optional camera/NFC/HCE features, and a service
protected by BIND_NFC_SERVICE. MainActivity extends FlutterFragmentActivity, with
AppCompat themes for local_auth. ML Kit remains bundled so scanning does not need
a first-use network download. [AppDelegate.swift](ios/Runner/AppDelegate.swift)
registers plugins/native NFC using Flutter's current implicit-engine lifecycle.

## Data and protocol

The requested `users` and `transactions` tables are created in
`lib/database/db_helper.dart`. Amounts remain REAL in SQLite as requested, but all
wallet arithmetic and validation use integer cents. Balance debit + insertion
and receipt + credit run inside SQLite transactions. Recipient binding is included
in both the signed payload and database. `receipts(tx_id PRIMARY KEY,
receiver_mobile, received_at)` prevents local replay, including concurrent scans.
The recipient account does not require the sender's account in its database.

HMAC-SHA256 covers canonical JSON with `version`, `tx_id`, `sender_mobile`,
`receiver_mobile`, `amount`, `timestamp`. A 192-bit random transaction ID avoids
ordinary collisions. Signatures exclude mutable sync status. Unknown/malformed
payloads, invalid/future timestamps (over five minutes), sub-cent values, wrong
recipient and conflicting transaction IDs are rejected. Keep device clocks set
correctly. No expiry is imposed on valid old unreceived transfers.

NFC uses demo AID `F0544150435045534F01`. SELECT returns a two-byte unsigned
big-endian payload length followed by `9000`; `00 B0 offsetHi offsetLo Le` reads
up to 192 bytes followed by `9000`. Maximum UTF-8 payload is 4096 bytes. Only the
explicitly offered, already-debited payment is held in volatile native memory.
Stopping/backgrounding Android clears the offer. No SharedPreferences, keychain,
files or cloud service are used for wallet persistence. The same payment remains
recoverable in SQLite history after process death.

## Prototype security and verification limits

The shared hardcoded demo HMAC key lets separate installations verify payments
offline. Anyone who extracts it can forge payments. `public_key_token` is a
random public account token used to salt the PIN hash, **not** an asymmetric key.
Four-digit SHA256 PIN hashes, local cash-in, unencrypted SQLite and a modified
client are not production money security. Device authentication is required for
send; no silent authentication bypass is provided.

Replay protection applies to the local database. Reinstalling/cloning a wallet,
restoring an old database or using the same account on multiple devices can
defeat it. An entirely local prototype cannot enforce global balances or prevent
offline double spending. Local sync verifies tokens, not bank settlement or
proof of receiver delivery. Delivery failure has no automatic refund: issuing a
refund while an offline token remains redeemable would create money.

Tests cover signature tampering, input validation, atomic debit/credit, same-device
receipt, external sender receipt, concurrent replay, insufficient funds, demo
setup, local sync and mocked native transport. **Flutter/Dart and native compiler
toolchains are absent in the authoring environment, so builds, Flutter tests and
physical NFC transfers have not been run here.** Follow the two-device checklist
on your hardware; NFC support and antenna placement vary. QR is the interoperable
offline fallback for every Android/iPhone pairing.

Available local checks passed: Python/PowerShell bootstrap syntax, Android XML,
iOS entitlements parsing, execution of the actual extracted SQLite schema and
its negative-balance / duplicate-receipt constraints, plus a lightweight source
delimiter scan. These do not substitute for Flutter analysis or device testing.
