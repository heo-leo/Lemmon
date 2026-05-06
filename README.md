[![macOS 10.10+](https://img.shields.io/badge/macOS-10.10+-888)](#)
[![Current release](https://img.shields.io/github/release/heo-leo/Lemmon)](https://github.com/heo-leo/Lemmon/releases/latest)
[![All downloads](https://img.shields.io/github/downloads/heo-leo/Lemmon/total)](https://github.com/heo-leo/Lemmon/releases)

<img src="img/icon.svg" width="180" height="180">


Lemmon (Leo's Memmon)
======

Lemmon remembers what your Mac forgets – A simple daemon that restores your window positions on external monitors. Forked from [relikd/Memmon](https://github.com/relikd/Memmon) with reliability fixes for monitor disconnect/reconnect.

**Limitations:**
- Currently, Lemmon restores windows in other spaces only if the space is activated.
- Support for the Mission Control config option "Displays have separate Spaces" is not tested
  (upstream issue [#5](https://github.com/relikd/Memmon/issues/5#issuecomment-1040611494)).


Usage
-----

Grant Lemmon the Accessibility privilege.
Go to "System Settings" > "Privacy & Security" > "Accessibility" and add Lemmon to that list.
(Otherwise, the app can't move application windows around.)


Installation
------------

Requires macOS Yosemite (10.10) or higher.

```sh
brew install --cask heo-leo/tap/lemmon
```

or download from [releases](https://github.com/heo-leo/Lemmon/releases/latest).

### macOS 10.14.3 or lower

You'll need the Swift 5 Runtime Support.
Download either from [Apple](https://developer.apple.com/download/all/) (developer account required)
or use [this dmg](https://github.com/relikd/Darker/raw/refs/heads/main/Swift_5_Runtime_Support.dmg).

### Build from source

- Run `make` to create an app bundle.
- OR: call the script directly (`swift src/main.swift`).
- OR: create a new Xcode project, select the Command-Line template, and replace the provided `main.swift` with this one.


Options
-------

### Menu Bar Icon

You can hide the menu bar icon either via `defaults` or the same-titled menu entry.
If you do so, the only way to quit the app is by killing the process (with Activity.app or `killall Lemmon`).
The menu bar icon stays hidden during this execution only. If you restart the OS or app it will reappear (unless you hide the icon with `defaults`).

Lemmon has exactly one app-setting, the menu bar icon.
You can manipulate the display of the icon, or hide the icon completely:

```sh
# disable menu bar icon completely
defaults write de.heo-leo.Lemmon icon -int 0
# Use window-dots-icon
defaults write de.heo-leo.Lemmon icon -int 1
# Use monitor-with-windows icon (default)
defaults write de.heo-leo.Lemmon icon -int 2
# re-enable menu bar icon and use default icon
defaults delete de.heo-leo.Lemmon icon
```

![menu bar icons](img/status_icons.png)


FAQ
---

### Why‽

I am frustrated!
Why does my Mac forget all window positions which I moved to a second screen?
Every time I unplug the monitor.
Every time I close my Macbook lid.
Every time I lock my Mac.

Is it macOS 11?
Is it the USB-C-to-HDMI converter dongle (notably one made by Apple)?
Why do I have to fix things that Apple should have fixed long ago? …


### Aren't there other solutions?

Yes, for example, you can use [Mjolnir](https://github.com/mjolnirapp/mjolnir) or [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) (and some comercial ones) to restore your perfect window setup on a button press.
But I do not need a full-fledged window manager or the dependencies it relies on.
Nor do I want to constantly adjust for new windows.
Actually, I don't want to think about this problem at all – I just want to fix this damn bug.


### What is it good for?

First off, Lemmon is less than 300 lines of code – no dependencies.
You can audit it in 10 minutes...
And build it from scratch.

Secondly, it does one thing and one thing only:
Save and restore window positions whenever your monitor setup changes.
