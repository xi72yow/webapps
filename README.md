# webapps

Web applications packaged as Debian packages and shipped through an APT repository on GitHub
Pages.

Two packaging backends live here, because the right answer differs per app:

| Backend | Size per app | Used for |
|---|---|---|
| **Chrome app launcher** | ~2 KB | Everything that just needs a window. A `.desktop` entry starting `chrome --app=<url>`. Depends on an installed Chrome. |
| **Electron wrapper** | ~310 MB | Apps that need their own Chromium flags. Currently only Teams. |

Chromium flags are process-wide, so a Chrome app launcher cannot carry flags that differ from your
main browser. When an app needs that, it needs its own process, which is what the Electron backend
provides. Everything else stays a launcher, because 310 MB of bundled Chromium per app is not worth
paying for a window.

## Install

```bash
wget -qO- https://xi72yow.github.io/webapps/pubkey.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/webapps.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/webapps.gpg] https://xi72yow.github.io/webapps stable main" \
  | sudo tee /etc/apt/sources.list.d/webapps.list

sudo apt update
sudo apt install teams outlook-desktop mattermost-desktop
```

Package names: the Electron wrapper is `teams`, every Chrome launcher is `<name>-desktop`. No APT
pin is needed, none of these names collide with a Debian package.

## Adding a Chrome app

Append an entry to `apps.json`:

```json
{
  "name": "outlook",
  "display_name": "Outlook",
  "url": "https://outlook.office.com/mail/",
  "icon": "brand-office",
  "color": "#0078d4",
  "categories": "Network;Email;",
  "version": "1.2.0"
}
```

Then `./scripts/make-icons.sh` followed by `./build.sh chrome outlook`. `StartupWMClass` is derived
from the URL the same way Chrome derives it, so GNOME associates the window with the launcher.

## Icons

The packages do not use the vendor logos. Those are third-party trademarks, so neither this repo
nor the packages may carry them. Instead `scripts/make-icons.sh` renders one icon per app from
[Tabler Icons](https://tabler.io/icons) (MIT): `icon` picks the glyph, `color` the tile behind it.

Until 1.1.0 the real logos were downloaded by `postinst`. That fails silently whenever PackageKit
applies an update offline during boot, because there is no network yet, and the app is then left
without an icon until the next reinstall.

The results live in `icons/` and are committed, so a build needs neither network nor the script.
Re-run it after changing `icon` or `color`; it also renders `electron/build/icon.png`, which
electron-builder needs as a PNG.

Bump `version` on an entry whenever you change it, otherwise APT sees no update.

## The Electron wrapper (Teams)

Lives in `electron/`. It exists because of a video call failure mode: some participants saw the
shared screen and camera, others did not. The cause is WebRTC simulcast. Chromium encodes several
quality layers in parallel and the Teams SFU forwards a different one to each receiver. When a
layer fails in the hardware encoder, exactly those receivers assigned to it see nothing.
Reproducible on AMD RDNA3 (VCN).

### Chromium flags

All set in `electron/src/main.js`.

| Flag | Reason |
|---|---|
| `--disable-features=VaapiVideoEncoder,AcceleratedVideoEncoder` | Forces software encoding for WebRTC, which fixes the simulcast layer dropout on RDNA3. Decoding is left untouched. |
| `--disable-features=UseMultiPlaneFormatForHardwareVideo` | White-frame bug with multi-plane video on RDNA3. |
| `--enable-features=WebRTCPipeWireCapturer` | Screen sharing under Wayland. Chromium delegates source selection to `xdg-desktop-portal`. |
| `--use-fake-ui-for-media-stream` | Suppresses Chromium's own permission prompt for camera, microphone and screen. |
| `--ozone-platform-hint=auto` | Native Wayland instead of XWayland, which would be blurry on HiDPI. |

Software encoding costs nothing measurable on a 9950X.

**Security implication of `use-fake-ui-for-media-stream`:** the app no longer asks before accessing
camera or microphone. The GNOME portal dialog still gates screen sharing, but camera and microphone
are granted silently. Acceptable in a window that only ever loads Teams.

### Screen share audio

`getDisplayMedia` is forced to `audio: false`. Reason: `use-fake-ui-for-media-stream` approves media
requests without asking, audio included. The screen share track then leaves as a second audio
channel alongside the microphone and other participants hear you twice. Confirmed on 2026-07-28:
the echo started exactly when sharing began and disappeared the moment it stopped.

teams-for-linux does the same, see `app/screenSharing/injectedScreenSharing.js`, comment "Force
disable all audio in screen sharing to prevent echo issues".

The patch targets `navigator.mediaDevices.getDisplayMedia`, a W3C API rather than Teams internals.
It is injected via `webContents.executeJavaScript` on `dom-ready`, because `contextIsolation: true`
keeps a preload script out of the page world.

### URL

Loads `https://teams.microsoft.com/v2`. Microsoft is consolidating the M365 surfaces onto the
dedicated domain `https://teams.cloud.microsoft`, which helps phishing resistance and allowlisting.
Both hosts are served in parallel and neither redirects to the other. The legacy path stays the
default because tenant policies, proxies and allowlists frequently only know that one. Switch
without rebuilding:

```bash
TEAMS_URL=https://teams.cloud.microsoft teams
```

Sessions are bound to the origin, so switching requires a fresh login. The domain has no effect on
call behaviour, simulcast and encoding live in the Chromium media stack.

### User agent

Teams gates features on a recognised browser string and Electron's default is not one of them, so
the wrapper reports itself as Edge on Linux. The value lives in `electron/src/main.js` and is
applied to popup windows too, so the sign-in flow sees the same browser.

### Windows and sign-in

- **Auth popups stay in the app.** Windows targeting `login.microsoftonline.com`, `login.live.com`
  and `login.windows.net` open as Electron windows, everything else is handed to the system
  browser. The list is `AUTH_HOSTS` in `electron/src/main.js`
- **Single instance lock.** A second launch focuses the existing window instead of opening another

### What it deliberately does not do

No tray icon, no unread badge, no presence, no background operation (closing the window quits the
app), no `msteams:` deep links, no custom backgrounds, no profile switching. The web Notification
API works natively, so ordinary desktop notifications do appear.

### Relation to teams-for-linux

`IsmaelMartinez/teams-for-linux` (GPL-3) is the established wrapper and does all of the above. The
price is roughly 4,700 lines of injections into the internals of the Teams web app, which can break
whenever Microsoft reworks the frontend. Its main window also runs with `contextIsolation: false`
and `sandbox: false`, because reaching into the React tree requires it. This wrapper needs only
Electron plumbing and keeps `contextIsolation: true` and `sandbox: true`.

Useful detail found in their code: under Wayland, Chromium hands screen source selection straight to
`xdg-desktop-portal` and bypasses `setDisplayMediaRequestHandler`, so no in-app picker is needed.

## Why some apps cannot move to Electron

Official Electron builds ship without Widevine, so DRM playback does not work. **Netflix and Spotify
have to stay Chrome launchers.** Adding DRM would mean switching to the castlabs build, which is not
worth it here.

## Building locally

```bash
./build.sh                  # everything
./build.sh chrome           # only the Chrome launchers
./build.sh chrome outlook   # only one of them
./build.sh electron         # only the Electron wrapper
```

Everything lands in `dist/`. The Chrome launchers need `jq` and `dpkg-dev` on the host. The Electron
build runs entirely inside a Podman container, nothing is installed on the host, and Electron
binaries are cached in `.cache/` so repeat builds are fast.

## Releasing

`.github/workflows/build.yml` builds both backends on every push and pull request. Publishing
happens on a **manual run** (Actions, Build, Run workflow) and on a pushed `v*.*.*` tag.

There is no version to bump by hand. Every package version gets `+<run_number>` appended during
the build, so each run automatically outranks the previous one:

```
apps.json says 1.1.0   ->  outlook-desktop_1.1.0+43_all.deb
package.json says 0.1.3 -> teams_0.1.3+43_amd64.deb
```

`+` is deliberate. `dpkg --compare-versions` orders `1.1.0+43` above `1.1.0+42` and above plain
`1.1.0`, and it stays valid semver, which a `-43` suffix would not: semver reads that as a
prerelease, ranking it *below* `1.1.0`.

The base versions in `apps.json` and `electron/package.json` are still yours to raise whenever a
change deserves a real version bump. They are just no longer required for APT to see an update.

A publishing run creates a GitHub release with every `.deb` and a `SHA256SUMS`, rebuilds the APT
repository via `scripts/update-apt-repo.sh` and deploys it to GitHub Pages. Manual runs name the
release `build-<run_number>`, tagged runs use the tag.

Locally the suffix is absent unless you ask for it:

```bash
BUILD_NUMBER=43 ./build.sh
```

Required repository setup:

- Secret `GPG_PRIVATE_KEY` with the armored private signing key. Without it the repo is published
  unsigned and `apt update` will reject it
- Pages source set to GitHub Actions

The APT pool is rebuilt from scratch on every release, so it only ever carries current versions.
Older builds remain available as GitHub release assets.

## Install layout

- Chrome launchers install a single `.desktop` file plus an icon, and depend on
  `google-chrome-stable`
- The Electron wrapper installs to `/opt/Teams`, launcher `/opt/Teams/teams`, with
  `StartupWMClass=teams`

Careful when editing the Electron maintainer scripts: electron-builder substitutes `${...}` as its
own macro. Write shell variables there without braces, otherwise the build aborts with
`Macro ... is not defined`.

## Maintenance

Electron is Chromium, so the Chromium CVE cadence applies to the `teams` package. Keep the
`electron` version in `electron/package.json` moving and rebuild. Dependabot is configured for that
and for the Actions.

The Chrome launchers carry no runtime of their own, they inherit whatever Chrome is installed, and
need no maintenance beyond a URL changing upstream.

## Verifying an encoder problem in a call

The encoder cannot be measured inside the Electron wrapper, it does not register the `chrome://`
pages. Measure in Chrome instead. The result carries over because the same Chromium media stack sits
underneath.

1. Start Chrome with its own profile and the same flags:
   ```bash
   google-chrome-stable --user-data-dir=/tmp/teams-test \
     --disable-features=VaapiVideoEncoder,AcceleratedVideoEncoder,UseMultiPlaneFormatForHardwareVideo \
     --app=https://teams.microsoft.com/v2
   ```
2. Start a meeting and join from a **phone on mobile data**. Because of the small display and
   narrower link it requests the low simulcast layer, which is the suspect one. Two tabs on the same
   machine both receive the high layer and test nothing
3. Mute both microphones, then share the screen and enable the camera on the desktop
4. In `chrome://webrtc-internals`, inspect each `rid` under `outbound-rtp`:
   - `encoderImplementation`: hardware or software
   - `framesEncoded`: must climb on **every** layer. One stuck at 0 is the bug
   - `mimeType`: H264 or VP8

Reading the result: if the sender encodes and `bytesSent` climbs while the receiver still sees
nothing, the problem is decoding or transport on the far side rather than the encoder.

## Open items

- Pin the base image in `electron/build/Containerfile` to a SHA256 digest
- Check whether `getDisplayMedia` succeeds without a registered `setDisplayMediaRequestHandler`.
  According to teams-for-linux the handler is bypassed on the Wayland PipeWire path. If screen
  sharing fails, add a trivial handler or set `useSystemPicker`
- Verify the Teams user agent does not collide with Conditional Access policies
- Confirm the simulcast fix in a real group call

## License

None. Private project, all rights reserved.
