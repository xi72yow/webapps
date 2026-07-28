const { app, BrowserWindow, shell } = require("electron");

// neue konsolidierte m365-domain waere https://teams.cloud.microsoft
// beide hosts werden parallel bedient, es gibt keinen redirect.
// umschaltbar per env, weil tenant-policies und proxies teils nur einen kennen:
//   TEAMS_URL=https://teams.cloud.microsoft teams
const TEAMS_URL = process.env.TEAMS_URL || "https://teams.microsoft.com/v2";

// teams gates features on a recognised browser, electron's default ua is not one
const USER_AGENT =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) " +
  "Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0";

// wayland: chromium delegates the screen share picker to xdg-desktop-portal,
// so no in-app picker is needed here
app.commandLine.appendSwitch("enable-features", "WebRTCPipeWireCapturer");
// suppresses chromium's own camera/mic/screen prompt, the portal dialog remains
app.commandLine.appendSwitch("use-fake-ui-for-media-stream");
// amd vcn drops simulcast layers, receivers on those layers see nothing
app.commandLine.appendSwitch(
  "disable-features",
  "VaapiVideoEncoder,AcceleratedVideoEncoder,UseMultiPlaneFormatForHardwareVideo",
);
app.commandLine.appendSwitch("ozone-platform-hint", "auto");

const AUTH_HOSTS = [
  "login.microsoftonline.com",
  "login.live.com",
  "login.windows.net",
  "microsoftonline.com",
];

// screen share audio goes out as a second track next to the mic, so others hear
// us twice. patches a w3c api, not teams internals, and runs in the page world
// via executeJavaScript because contextIsolation keeps the preload separate
const STRIP_SHARE_AUDIO = `
(() => {
  const md = navigator.mediaDevices;
  if (!md || md.__shareAudioStripped) return;
  const original = md.getDisplayMedia.bind(md);
  md.getDisplayMedia = (constraints = {}) =>
    original(Object.assign({}, constraints, { audio: false }));
  md.__shareAudioStripped = true;
})();
`;

let mainWindow = null;

function isAuthUrl(url) {
  try {
    return AUTH_HOSTS.includes(new URL(url).hostname);
  } catch {
    return false;
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      spellcheck: true,
    },
  });

  // auth popups stay in-app, anything else opens in the default browser
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isAuthUrl(url)) {
      return {
        action: "allow",
        overrideBrowserWindowOptions: {
          width: 800,
          height: 700,
          autoHideMenuBar: true,
        },
      };
    }
    shell.openExternal(url);
    return { action: "deny" };
  });

  // popups inherit the ua so the auth flow sees the same browser
  app.on("browser-window-created", (_event, window) => {
    window.webContents.setUserAgent(USER_AGENT);
  });

  // teams is an spa, so re-apply after every document load
  mainWindow.webContents.on("dom-ready", () => {
    mainWindow.webContents.executeJavaScript(STRIP_SHARE_AUDIO).catch(() => {});
  });

  mainWindow.loadURL(TEAMS_URL, { userAgent: USER_AGENT });
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });

  app.whenReady().then(createWindow);

  app.on("window-all-closed", () => app.quit());
}
