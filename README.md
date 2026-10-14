# MenuBar Manager

A small, personal menu bar manager for macOS 27, in the spirit of Ice and Thaw. It hides menu bar icons you rarely use and shows them when you click.

## What it does

- Adds an arrow to the menu bar. Click it to hide or show the icons of the apps you chose; right-click (or Control-click) it for Settings and Quit.
- On macOS 27 hiding works app by app: in Settings, tick the apps whose icons should be hidden. Apple's own items (clock, Wi-Fi, battery, Control Center) always stay.
- Hidden icons come back on their own after a few seconds (5 by default), or when you switch apps. It waits while the pointer is in the menu bar or a menu is open.
- Works on every display at once.
- Rearrange visible icons with the built-in Command-drag. macOS remembers the positions.
- Opening the app again from Spotlight or Finder shows everything and opens Settings, which is the way back if the arrow ever goes missing.
- Launch at login from Settings.

## Permissions

Hiding needs no permission. Accessibility, which Settings offers to turn on, lets the app list only apps that actually have menu bar icons; without it the list shows every running app.

Sign builds with your Apple Development identity (the build script does this automatically): ad hoc builds get a new identity every time, and macOS forgets the permission after each rebuild.

## Build and install

Requires macOS 27 on Apple silicon and Xcode 27 (command line tools are enough).

```bash
./scripts/build-app.sh --install
```

This builds a release binary, wraps it in `MenuBar Manager.app`, signs it with your Apple Development or Developer ID identity (or ad hoc if none), copies it to `/Applications` and launches it. Launch at login works best from `/Applications`.

To work in Xcode instead, open `Package.swift`. Run the `MenuBarManager` scheme; note that launch at login needs the bundled app from the script.

## How it works

macOS 27 draws the whole menu bar in a single window owned by MenuBarAgent, so the classic trick of stretching a divider item to push icons off screen no longer does anything. Instead the app holds an "assessment mode" assertion from the private MenuBarClientCore framework: while it is live, only the system items and the apps on its allowlist keep their icons. The allowlist is every running app except the ones you chose to hide. It only covers apps running when it was made, so it is remade whenever an app launches or quits, and a hidden app that is just launching is shown for a few seconds while it creates its icon.

The technique comes from Thaw's PlatformRuntimeKit and Ice's macOS 27 work (jordanbaird/Ice#995 and #1001). This app has its own implementation.

Diagnostics go to `~/Library/Logs/MenuBarManager.log`.

## Reset

To start over with no hidden apps and the welcome screen:

```bash
defaults delete com.skinred78.MenuBarManager
```

The spec lives in the project doc "MenuBar Manager Spec".
