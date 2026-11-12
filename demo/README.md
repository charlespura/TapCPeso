# Interactive app demo

Open **interactive.html** (or **index.html** / **tapcpeso-demo.html**) in Chrome,
Edge, Firefox or Safari. These are identical self-contained files: share any one
HTML file. No server, installation, external assets or internet is needed for the
wallet simulation. The optional speech guide uses your browser's installed voices;
voice availability and offline speech support depend on the browser/device.

There is no playback timeline or automatic slide progression. Buttons and forms
change real session state. On small screens use the Phone A / Phone B tabs.

Use **Watch 1-min demo** in the header for the narrated video overlay. Keep
`tapcpeso-demo.mp4` beside the HTML when sharing this player. The wallet simulation
itself remains self-contained if you share only the HTML.

1. Click **Set up both demo wallets**. Each phone starts with PHP 1,000.
2. On phone A choose **Add money** and enter, for example, `100.00`.
3. Choose **Send**, receiver `09172222222`, amount `25.00`. Enter PIN `1234` and
   approve the simulated fingerprint/device-passcode prompt.
4. Phone A becomes PHP 1,075. Choose **Simulate receiver scanning QR** or
   **Simulate NFC tap**. Phone B opens the delivered token.
5. On phone B choose **Validate & receive payment**. Its balance becomes PHP 1,025.
6. Re-deliver that same token and accept again: a duplicate is rejected.
7. Choose **Simulate reconnect & sync** on both phones. Status changes, balances do not.

You can register your own accounts, switch between local accounts, cancel an
authorization, enter other amounts, inspect/copy/paste tokens, view history and
reset the demo. PINs are salted SHA256 hashes in session memory. Tokens use HMAC
SHA256 and integer cents. Browser-demo tokens deliberately differ from real
Flutter transaction payloads and cannot be used as native wallet payments.

**Simulation boundaries:** browser QR art is illustrative and not scannable;
delivery buttons move tokens between the two panels. No camera, NFC radio or real
biometrics are used. No wallet data is written to localStorage or a server. Reload
resets all data. The actual Flutter application continues using SQLite and native
authentication/NFC code. This browser preview does not replace device testing or
provide production money security.

Browser QA: `node tool/check-interactive.mjs` exercises registration, cash-in,
incorrect PIN, cancellation, insufficient funds, debit/credit, QR delivery, NFC
replay, signature tampering, recipient binding, sync, reset, guide progression,
and mobile tabs/overflow. SHA256/HMAC are cross-checked against Node's crypto.
Results are saved in `interactive-verification.json`, with desktop/mobile
screenshots in `previews/`. Narration availability/quality was not audio-tested.

## One-minute moving-interface video

The MP4 now uses TapCPeso's green Material-style wallet UI with smooth scene
transitions, typed fields, tap cursors, authentication animation, QR scanning,
moving payment tokens, balance counters, local replay rejection and sync status
changes. The supplied recording guided the motion/presentation only; its other
app's colors, globe interface, name and content were not copied.

Open **tapcpeso-demo.mp4** to watch or share it through a messaging app, email,
presentation, or social media. It is a 1280 × 720 landscape MP4 with English
synthetic narration and captions burned into the picture. A separate SRT file is
included for players that accept subtitle tracks.

The original animation source is retained as **video-source.html**. It expects
**demo-data.js** and **motion-graphics.js** beside it. Rebuilding creates **tapcpeso-video.html**, the embedded
video-style player, without overwriting the interactive app demo.

## What viewers see

| Time | Flow |
| --- | --- |
| 00:00–00:06 | Introduce the offline wallet prototype |
| 00:06–00:14 | Quick Demo Setup and two local accounts |
| 00:14–00:22 | Dashboard and mock cash-in |
| 00:22–00:31 | Recipient, amount, wallet PIN and device authorization |
| 00:31–00:40 | Deduct once and deliver by QR or supported native NFC |
| 00:40–00:48 | Verify, credit receiver, and reject a local replay |
| 00:48–00:55 | Review history and simulate local signature sync |
| 00:55–01:00 | Explain prototype and hardware-testing limits |

These are illustrated screens based on the implemented flow, **not a recording
of the Flutter app running on a phone**. Narration uses the installed Microsoft
Zira synthetic English voice. Hardware NFC remains unverified. Android HCE can
send to compatible Android/iPhone readers; iPhone sending uses QR. Local replay
checks do not prevent global double spending across cloned/reinstalled wallets.

## Rebuild

On Windows, from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File tool\narrate-demo.ps1
node tool\render-demo.mjs
python tool\demo-captions.py
python tool\verify-demo.py
```

Requires the installed Windows Zira voice, Node 22+ and Chrome. Rendering launches
a hidden, dedicated Chrome profile under `.dart_tool/demo-chrome`, records a
minute of canvas animation plus narration, and closes that browser afterward.
`CHROME_PATH` can override the Chrome executable. Edit `storyboard.json` for
narration/timing and `video-source.html` for video visuals. Re-rendering updates the standalone
HTML and MP4. `verification.json` records the encoded duration and dimensions;
`previews/encoded-video.png` is decoded from the exported video.
