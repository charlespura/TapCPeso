# React + TypeScript interactive app demo

The main demo is now a React application written in strict TypeScript and built
with Vite. Its design, two-wallet simulation, optional voice guide and video player
are preserved. The native Flutter application remains separate.

## Run locally

Install Node.js 24 LTS, then from the repository root:

```sh
cd demo
npm ci
npm run dev
```

Open the localhost URL printed by Vite. On Windows PowerShell, use `npm.cmd` if
PowerShell blocks the `npm.ps1` launcher. Do not double-click `demo/index.html`:
it is now a Vite entry point that imports TypeScript/React source.

```sh
npm run typecheck
npm run build
npm run preview
```

Build output is `demo/dist/`: HTML, compiled JavaScript/CSS, and the narrated MP4.
The video is copied from `demo/tapcpeso-demo.mp4` by the build; no manual asset
copy is needed. Only this build output is deployed, not Flutter files, source
recordings, narration WAVs or preview screenshots. Relative asset URLs and
`import.meta.env.BASE_URL` let the same build work under `/REPOSITORY/` as well
as a root domain. The optional voice guide uses browser/OS speech voices.

## Deploy to GitHub Pages

The workflow is [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).
It installs from `demo/package-lock.json`, runs TypeScript checks and the Vite
build, uploads `demo/dist`, and deploys it using the official Pages actions.

1. Commit/push the source, `demo/package-lock.json`, MP4, and workflow to your
   GitHub repository. Generated `node_modules` and `dist` are ignored.
2. In the repository, choose **Settings → Pages → Build and deployment → Source:
   GitHub Actions**.
3. Push a demo change to **main**, or open **Actions → Deploy TapCPeso demo to
   GitHub Pages → Run workflow**.
4. Open the published URL shown in the deployment, normally
   `https://YOUR-USERNAME.github.io/YOUR-REPOSITORY/`.

No personal access token or cloud backend secrets are required. The workflow uses
GitHub's temporary token with Pages/OIDC permissions. If your default branch has
a different name, change `push.branches` in the workflow. For a private repository,
GitHub Pages availability depends on your plan. Actual publication runs in your
GitHub account; it has not been triggered from this workspace.

See [Vite's GitHub Pages guide](https://vite.dev/guide/static-deploy#github-pages)
and [GitHub's custom Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

## Code organization

- `src/main.tsx`: React entry point.
- `src/App.tsx`: React screens, forms, wallet panels, voice guide and video dialog.
- `src/types.ts`: typed accounts, payments, devices and modal state.
- `src/wallet.ts`: observable session state, wallet actions and validation.
- `src/crypto.ts`: browser-local SHA256/HMAC and exact cent parsing.
- `src/styles.css`: preserved responsive TapCPeso styling.
- `vite.config.ts`: relative deployment base and MP4 build packaging.

The legacy `interactive.html` and `tapcpeso-demo.html` copies remain available as
standalone HTML snapshots. They are not the React source or the Pages entry point.
`tool/add-demo-player.py` updates only those legacy copies and cannot overwrite
the React `index.html`.

## Try the wallet flow

There is no playback timeline or automatic slide progression. Buttons and forms
change real session state. On small screens use the Phone A / Phone B tabs.

Use **Watch 1-min demo** in the header for the narrated video overlay. The React
build includes the video automatically. If sharing a legacy standalone HTML
snapshot, keep `tapcpeso-demo.mp4` beside it for video playback.

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

Browser QA: after `npm run build` in `demo`, run `node tool/check-interactive.mjs`
from the repository root. It serves the compiled React app under `/TapCPeso/`
to exercise project Pages paths. It checks registration, cash-in,
incorrect PIN, cancellation, insufficient funds, debit/credit, QR delivery, NFC
replay, signature tampering, recipient binding, sync, reset, guide progression,
and mobile tabs/overflow. SHA256/HMAC are cross-checked against Node's crypto.
It also verifies the video loads, pauses on close, and does not break mobile
layout, and fails on missing production assets. Results are saved in
`interactive-verification.json`, with desktop/mobile
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
