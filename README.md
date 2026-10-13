# MenuBar Manager

A small, personal menu bar manager for macOS 27, in the spirit of Ice and Thaw. It hides menu bar icons you rarely use and shows them when you click.

## What it does (core app, milestone 2)

- Adds two items to the menu bar: an arrow and a thin divider line.
- Icons left of the divider are hidden. Click the arrow to show them, click again to hide.
- Hidden icons come back on their own after a few seconds (5 by default), or when you switch apps. It waits while the pointer is in the menu bar or a menu is open.
- Rearrange with the built-in Command-drag. macOS remembers the positions.
- Click the divider (while icons are shown) for **Edit Layout**, **Settings** and **Quit**. Edit Layout keeps everything visible until you click the arrow or untick it.
- Works on every display: macOS mirrors the divider to each display's menu bar.
- Launch at login from Settings.

The bar below the menu bar for notched displays is milestone 3.

## Build and install

Requires macOS 27 on Apple silicon and Xcode 27 (command line tools are enough).

```bash
./scripts/build-app.sh --install
```

This builds a release binary, wraps it in `MenuBar Manager.app`, signs it with your Apple Development or Developer ID identity (or ad hoc if none), copies it to `/Applications` and launches it. Launch at login works best from `/Applications`.

To work in Xcode instead, open `Package.swift`. Run the `MenuBarManager` scheme; note that launch at login needs the bundled app from the script.

## How it works

The divider is an ordinary status item owned by this app. Hiding stretches it to 10,000 points wide, which pushes everything to its left off the screen; revealing shrinks it back. Other apps' icons are never moved or modified. If the divider ends up to the right of the arrow, the app refuses to hide and explains how to fix it, so you can't lock yourself out.

On macOS 27 a click on a status item may start an "expanded interface session" instead of sending the button's action, so the arrow listens for both.

## Reset

To start over with default positions and the welcome screen:

```bash
defaults delete com.skinred78.MenuBarManager
```

The spec lives in the project doc "MenuBar Manager Spec".
