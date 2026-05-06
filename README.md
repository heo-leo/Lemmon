[![macOS 10.10+](https://img.shields.io/badge/macOS-10.10+-888)](#)
[![Current release](https://img.shields.io/github/release/relikd/Memmon)](https://github.com/relikd/Memmon/releases/latest)
[![All downloads](https://img.shields.io/github/downloads/relikd/Memmon/total)](https://github.com/relikd/Memmon/releases)

<img src="img/icon.svg" width="180" height="180">


Lemmon (Leo's Memmon)
======

Memmon remembers what your Mac forgets – A simple deamon that restores your window positions on external monitors.

**Limitations:**
- Currently, Memmon restores windows in other spaces only if the space is activated.
  If you know a way to access the accessibility settings of a different space, let me know.
- Support for the Misson Control config option “Displays have separate Spaces” is not tested.
  I will add support for this as soon as I have access to an external monitor again (issue [#5](https://github.com/relikd/Memmon/issues/5#issuecomment-1040611494)).


Usage
-----

Grant Memmon the Accessibility privilege.
Go to "System Preference" > "Security & Privacy" > "Accessibility" and add Memmon to that list.
(Otherwise, the app can't move application windows around)


Installation
------------

Requires macOS Yosemite (10.10) or higher.

```sh
brew install --cask relikd/tap/memmon
xattr -d com.apple.quarantine /Applications/Memmon.app
```

or download from [releases](https://github.com/relikd/Memmon/releases/latest).

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
If you do so, the only way to quit the app is by killing the process (with Activity.app or `killall Memmon`).
The menu bar icon stays hidden during this execution only. If you restart the OS or app it will reappear (unless you hide the icon with `defaults`).

Memmon has exactly one app-setting, the menu bar icon.
You can manipulate the display of the icon, or hide the icon completely:

```sh
# disable menu bar icon completely
defaults write de.relikd.Memmon icon -int 0
# Use window-dots-icon
defaults write de.relikd.Memmon icon -int 1
# Use monitor-with-windows icon (default)
defaults write de.relikd.Memmon icon -int 2
# re-enable menu bar icon and use default icon
defaults delete de.relikd.Memmon icon
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

First off, Memmon is less than 300 lines of code – no dependencies.
You can audit it in 10 minutes...
And build it from scratch.

Secondly, it does one thing and one thing only:
Save and restore window positions whenever your monitor setup changes.
