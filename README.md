# WhatsApp Lock

A small macOS menu bar utility that PIN-protects the WhatsApp desktop app on
this Mac. Whenever WhatsApp is launched or brought to the front — including
switching back to it with Cmd+Tab or the Dock after using another app —
WhatsApp Lock immediately hides it and shows a PIN prompt. Only the correct
PIN (or Touch ID, on Macs that have it) unhides it; entering the PIN wrong or
cancelling quits WhatsApp instead. WhatsApp only stays unlocked while it's
the active app; switching away and back re-locks it, same as fully closing
and reopening it.

It is a **local, single-device, self-discipline tool** — not enterprise
security. See "Honest limitations" below before you rely on it.

## What's in this project

- `Package.swift` — Swift Package Manager manifest (no external dependencies).
- `Sources/WhatsAppLock/`
  - `main.swift` — entry point, runs as a menu-bar-only (accessory) app.
  - `AppDelegate.swift` — wires everything together: status bar menu, PIN
    setup, and reacting to WhatsApp launching.
  - `AppMonitor.swift` — watches for WhatsApp launching/activating/quitting
    via `NSWorkspace` notifications, auto-detecting WhatsApp's bundle ID
    from the installed app.
  - `PINManager.swift` — stores a salted SHA-256 hash of your PIN (never the
    PIN itself) in `~/Library/Application Support/WhatsAppLock/config.json`,
    with a short lockout after 5 wrong attempts.
  - `BiometricAuthenticator.swift` — offers Touch ID (via LocalAuthentication)
    as a faster alternative to typing the PIN, on Macs that have it. Touch ID
    attempt limiting is handled by the Secure Enclave itself, independent of
    the PIN's own 5-attempt lockout.
  - `PINPromptWindowController.swift` — the "enter PIN" window, reused both
    to unlock WhatsApp and to confirm sensitive actions in WhatsApp Lock
    itself (quitting, turning off auto-start, changing the PIN).
  - `PINSetupWindowController.swift` — first-run "choose a PIN" window.
  - `LaunchAgentManager.swift` — installs/removes a per-user LaunchAgent so
    WhatsApp Lock starts at login and restarts itself if killed.
- `Resources/Info.plist` — bundle metadata used when packaging the final
  `.app` (sets it to run with no Dock icon).
- `Scripts/build_app.sh` — builds a release binary and assembles
  `dist/WhatsApp Lock.app`.
- `Scripts/make_dmg.sh` — packages that `.app` into `dist/WhatsApp Lock.dmg`
  with an `/Applications` shortcut, ready to drag-install.

## Requirements

- macOS 13 or later.
- Xcode (or at least the Xcode Command Line Tools: `xcode-select --install`).
- WhatsApp for Mac installed in `/Applications/WhatsApp.app` (the normal
  install location). If it's not there yet when WhatsApp Lock first runs,
  it falls back to WhatsApp's known bundle IDs, so it should still work —
  but install WhatsApp first if possible.

## Try it during development

From this folder:

```bash
swift run
```

This builds and runs WhatsApp Lock directly (you'll see a lock icon appear
in the menu bar). First run asks you to set a PIN. Open WhatsApp to test —
it should immediately hide and prompt for the PIN.

Note: while running this way, "Start at Login" would point at a temporary
build path under `.build/`, so don't turn that on yet — do that after
installing the final built app (next section).

You can also just open this folder in Xcode (`File > Open...` and select
the `WhatsAppLock` folder, or `Package.swift` directly) and hit Run there.

## Build the real app + DMG

```bash
./Scripts/build_app.sh    # -> dist/WhatsApp Lock.app
./Scripts/make_dmg.sh     # -> dist/WhatsApp Lock.dmg
```

Then:

1. Open `dist/WhatsApp Lock.dmg` and drag **WhatsApp Lock** into
   `Applications`.
2. The app isn't notarized (it's ad-hoc signed for local use only), so the
   first time you open it from `/Applications`, right-click it and choose
   **Open**, then confirm — macOS Gatekeeper will only warn once.
3. Set your PIN when prompted.
4. From the menu bar icon's menu, turn on **Start at Login** now that you're
   running the real installed copy (this writes a LaunchAgent that points at
   `/Applications/WhatsApp Lock.app`).

## Changing the PIN / quitting / turning off auto-start

All three require your current PIN (or Touch ID) first — click the lock icon
in the menu bar and choose the action. Quitting is gated no matter how it's
requested: the menu item, Activity Monitor's plain **Quit** button, an
AppleScript `quit` command, or a plain `kill <pid>` from Terminal all funnel
through the same PIN/Touch ID prompt before the app is allowed to exit. This
is meant to stop *impulsive* bypassing, not a determined one (see below).

## Honest limitations

This app runs as your own user, like any other Mac app — it has no special
system privileges. That means:

- `kill -9 <pid>` and Activity Monitor's **Force Quit** button send SIGKILL,
  which no process on any Unix system — this one included — can intercept,
  delay, or refuse. That's a deliberate kernel guarantee (it's *why* SIGKILL
  exists: to always be able to kill a process no matter what it does), not a
  gap specific to this app. If you deliberately do this, WhatsApp Lock stops
  working immediately, no PIN required.
- If "Start at Login" is on and you `launchctl unload` the LaunchAgent, the
  PIN prompt still appears first (it's the same gated quit path), but if you
  ignore that prompt, launchd eventually escalates to SIGKILL after its own
  timeout and kills it anyway.
- If you want it meaningfully harder to bypass (needing an admin password to
  remove), that requires installing it as a root-owned LaunchDaemon via a
  `.pkg` installer instead of a plain `.dmg` — a bigger step; happy to build
  that version if you decide you want it later.
- It only guards the WhatsApp **desktop app**. It does not block
  `web.whatsapp.com` in a browser — that would need a separate browser
  extension or content-blocking rule.
- If WhatsApp is running fullscreen on a separate macOS Space, the PIN
  window may not visibly appear above it on some macOS versions; switching
  back to WhatsApp Lock's Space (or Mission Control) will show it.

## Uninstalling

1. Menu bar icon → enter PIN → **Turn off Start at Login**.
2. Quit WhatsApp Lock (menu bar icon → enter PIN → **Quit**).
3. Delete `/Applications/WhatsApp Lock.app`.
4. Optionally delete your saved PIN data:
   `rm -rf ~/Library/Application\ Support/WhatsAppLock`
