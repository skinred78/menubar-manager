# MenuBar Manager

A small, personal menu bar manager for macOS 27, in the spirit of Ice and Thaw. It hides menu bar icons you rarely use and shows them when you click.

## What it does

- Adds two items to the menu bar: an arrow and a thin divider line.
- Icons left of the divider are hidden. Click the arrow to show them, click again to hide.
- Hidden icons come back on their own after a few seconds (5 by default), or when you switch apps. It waits while the pointer is in the menu bar or a menu is open.
- Rearrange with the built-in Command-drag. macOS remembers the positions.
- Click the divider (while icons are shown) for **Edit Layout**, **Settings** and **Quit**. Edit Layout keeps everything visible until you click the arrow or untick it.
- Works on every display: macOS mirrors the divider to each display's menu bar.
- Launch at login from Settings.
- **Bar below the menu bar:** on a display with a notch, clicking the arrow opens a slim bar under the menu bar showing the hidden icons, so none get lost behind the notch. Click an icon there and its own menu opens. Settings lets you use the bar on every display, only notched ones (default), or never.

## Permissions

The hiding itself needs no permissions. The bar below the menu bar asks for two, once, the first time it opens:

- **Accessibility** lets a click in the bar open the real icon's menu. Without it the click just reveals the hidden icons so you can click them yourself.
- **Screen Recording** lets the bar show the real icons. Without it the bar shows each app's icon instead.

Both can be checked and granted from Settings. Sign builds with your Apple Development identity (the build script does this automatically): ad hoc builds get a new identity every time, and macOS forgets the permissions after each rebuild.

## Build and install

Requires macOS 27 on Apple silicon and Xcode 27 (command line tools are enough).

```bash
./scripts/build-app.sh --install
```

This builds a release binary, wraps it in `MenuBar Manager.app`, signs it with your Apple Development or Developer ID identity (or ad hoc if none), copies it to `/Applications` and launches it. Launch at login works best from `/Applications`.

To work in Xcode instead, open `Package.swift`. Run the `MenuBarManager` scheme; note that launch at login needs the bundled app from the script.

## How it works

The divider is an ordinary status item owned by this app. Hiding stretches it to 10,000 points wide, which pushes everything to its left off the screen; revealing shrinks it back. Other apps' icons are never moved or modified. If the divider ends up to the right of the arrow, the app refuses to hide and explains how to fix it, so you can't lock yourself out.

The bar finds hidden icons from the window list (their windows sit left of the divider), captures their pixels with ScreenCaptureKit (with a timeout, falling back to the app icon), and opens an icon by revealing the hidden section and pressing the item through Accessibility. It never moves other apps' icons.

On macOS 27 a click on a status item may start an "expanded interface session" instead of sending the button's action, so the arrow listens for both.

## Reset

To start over with default positions and the welcome screen:

```bash
defaults delete com.skinred78.MenuBarManager
```

The spec lives in the project doc "MenuBar Manager Spec".
