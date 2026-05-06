#!/usr/bin/env swift
import Cocoa
import AppKit

typealias AppPID = Int32  // see kCGWindowOwnerPID
typealias WinNum = Int  // see kCGWindowNumber (Int32) and NSWindow.windowNumber (Int)
typealias WinPos = (WinNum, CGRect)  // win-num, bounds
typealias WinConf = [AppPID: [WinPos]]  // app-pid, window-list
typealias SpaceId = WinNum  // see NSWindow.windowNumber (Int)

// Private AX SPI used by every macOS window manager to map AX windows back to
// their CGWindowID. Without it, AX windows can only be matched to CGWindow
// snapshots positionally, which fails as soon as the two lists differ in length
// (e.g. Chrome reports many auxiliary AXWindows but only a few CG-visible ones).
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var numScreens: Int = NSScreen.screens.count
	private var state: [Int: WinConf] = [:]  // [screencount: [pid: [windows]]]

	// captured before macOS rearranges windows on display change; consumed in applicationDidChangeScreenParameters
	private var preChangeSnapshot: WinConf? = nil
	private var preChangeNumScreens: Int = 0

	private var spacesAll: [SpaceId] = []  // keep forever (and keep order)
	private var spacesVisited: Set<WinNum> = []  // fill-up on space-switch
	private var spacesNeedRestore: Set<SpaceId> = []  // dropped after restore

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		// show Accessibility Permissions popup
		AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() : true] as CFDictionary)
		// track space changes
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.activeSpaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
		// snapshot window positions BEFORE macOS rearranges them on display add/remove.
		// applicationDidChangeScreenParameters fires after macOS has already moved/resized
		// windows to fit the new layout, so reading positions there saves corrupted values.
		CGDisplayRegisterReconfigurationCallback({ (_, flags, userInfo) in
			guard let userInfo = userInfo else { return }
			let me = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
			if flags.contains(.beginConfigurationFlag) && me.preChangeSnapshot == nil {
				me.preChangeSnapshot = me.getState()
				me.preChangeNumScreens = NSScreen.screens.count
			}
		}, Unmanaged.passUnretained(self).toOpaque())
		_ = self.currentSpace()  // create space-id win for current space
		self.spacesVisited = Set(self.getWinIds())
		// create status menu icon
		UserDefaults.standard.register(defaults: ["icon": 2])
		let icon = UserDefaults.standard.integer(forKey: "icon")
		if icon == 0 { return }
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = self.statusItem.button {
			switch icon {
			case 1: button.image = NSImage.statusIconDots
			case 2: button.image = NSImage.statusIconMonitor
			default: button.image = NSImage.statusIconMonitor
			}
		}
		self.statusItem.menu = NSMenu(title: "")
		self.statusItem.menu!.addItem(withTitle: "Memmon (v1.5)", action: nil, keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Hide Status Icon", action: #selector(self.enableInvisbleMode), keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
	}

	@objc func enableInvisbleMode() {
		self.statusItem = nil
	}

	func applicationDidChangeScreenParameters(_ notification: Notification) {
		if self.numScreens != NSScreen.screens.count {
			let snap = self.preChangeSnapshot
			let snapNum = self.preChangeNumScreens != 0 ? self.preChangeNumScreens : nil
			self.preChangeSnapshot = nil
			self.preChangeNumScreens = 0
			self.saveState(snapshot: snap, snapshotNumScreens: snapNum)
			self.numScreens = NSScreen.screens.count
			self.spacesVisited.removeAll(keepingCapacity: true)
			self.restoreState()
			// Displays often come online stepwise on reconnect; AX rejects positions outside
			// any currently-known display rect, so windows headed for a still-arriving display
			// can get clamped onto the primary one. Re-apply once everything has settled.
			self.scheduleRetry(after: 0.4)
			self.scheduleRetry(after: 1.5)
		}
	}

	private func scheduleRetry(after delay: TimeInterval) {
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
			guard let self = self else { return }
			self.spacesNeedRestore = Set(self.spacesAll)
			self.restoreState()
		}
	}
	
	private func getWinIds(allSpaces: Bool = false) -> [WinNum] {
		NSWindow.windowNumbers(options: allSpaces ? [.allApplications, .allSpaces] : .allApplications)?.map{ $0.intValue } ?? []
	}
	
	// MARK: - Save State (CGWindow) -
	
	private func saveState(snapshot: WinConf? = nil, snapshotNumScreens: Int? = nil) {
		self.spacesNeedRestore = Set(self.spacesAll)
		let oldNum = snapshotNumScreens ?? self.numScreens
		if self.state[oldNum] == nil {
			self.state[oldNum] = [:]  // otherwise state.keys wont run
		}
		let newState = snapshot ?? self.getState()
		let dummy: WinPos = (0, CGRect.zero)
		for kNum in self.state.keys {
			let isCurrent = kNum == oldNum
			// For non-current screen counts, seed with the existing snapshot so apps/windows that
			// are temporarily missing from newState (e.g., apps that hide windows when their
			// display disconnects) don't get dropped. For the current screen count, start fresh.
			var tmp_state: WinConf = isCurrent ? [:] : (self.state[kNum] ?? [:])
			for (n_app, n_windows) in newState {
				if let old_windows = self.state[kNum]![n_app] {
					var win_arr: [WinPos] = []
					var seen: Set<WinNum> = []
					for n_win in n_windows {
						seen.insert(n_win.0)
						// In theory, every space that was visited, was also restored.
						// If not visited (and not restored) then windows may still appear minimized,
						// so we rather copy the old value, assuming windows weren't moved while in an unvisited space.
						if isCurrent && self.spacesVisited.contains(n_win.0) {
							win_arr.append(n_win)
						} else {
							// caution! the positions of all other states are updated as well.
							let old_win = old_windows.first { $0.0 == n_win.0 }
							win_arr.append(old_win ?? dummy)
						}
					}
					if !isCurrent {
						// Preserve old windows whose winNum isn't currently visible; otherwise a
						// disconnect that hides windows on a vanishing display would erase their
						// saved positions.
						for ow in old_windows where !seen.contains(ow.0) {
							win_arr.append(ow)
						}
					}
					tmp_state[n_app] = win_arr
				} else if isCurrent {  // and not saved yet
					tmp_state[n_app] = n_windows
				}
			}
			self.state[kNum] = tmp_state
		}
	}
	
	private func getState() -> WinConf {
		let allWinNums = self.getWinIds(allSpaces: true).filter { !self.spacesAll.contains($0) }
		var state: WinConf = [:]
		let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
		
		for entry in windowList! {
			// let owner = entry[kCGWindowOwnerName as String] as! String
			if entry[kCGWindowLayer as String] as! CGWindowLevel != kCGNormalWindowLevel {
				continue
			}
			let winNum = entry[kCGWindowNumber as String] as! WinNum
			guard let insIdx = allWinNums.firstIndex(of: winNum) else {
				continue
			}
			let pid = entry[kCGWindowOwnerPID as String] as! AppPID
			let b = entry[kCGWindowBounds as String] as! [String: Int]
			let bounds = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
			if (state[pid] == nil) {
				state[pid] = [(winNum, bounds)]
			} else {
				// allWinNums is sorted by recent activity, windowList is not. Keep order while appending.
				if let idx = state[pid]!.firstIndex(where: { insIdx < allWinNums.firstIndex(of: $0.0)! }) {
					state[pid]!.insert((winNum, bounds), at: idx)
				} else {
					state[pid]!.append((winNum, bounds))
				}
			}
		}
		return state
	}
	
	// MARK: - Restore State (AXUIElement) -

	private func restoreState() {
		if let space = currentSpace(), self.spacesNeedRestore.contains(space) {
			self.spacesNeedRestore.remove(space)
			let spaceWinNums = self.getWinIds()
			self.spacesVisited.formUnion(spaceWinNums)
			for (pid, bounds) in self.state[self.numScreens] ?? [:] {
				self.setWindowSizes(pid, bounds.filter{ spaceWinNums.contains($0.0) })
			}
		}
	}
	
	private func setWindowSizes(_ pid: pid_t, _ sizes: [WinPos]) {
		guard sizes.count > 0 else { return }
		// Map each AX window to its CGWindowID so we can match by winNum instead of
		// by list index. AX may legitimately return more windows than CGWindowList
		// (auxiliary panels, hidden tabs), so an index/count match would silently
		// skip entire apps whenever the two lists diverge.
		var axByWin: [WinNum: AXUIElement] = [:]
		for ax in self.axWinList(pid) {
			var cgID: CGWindowID = 0
			if _AXUIElementGetWindow(ax, &cgID) == .success && cgID != 0 {
				axByWin[WinNum(cgID)] = ax
			}
		}
		for (winNum, rect) in sizes {
			var pt = rect
			if pt.isEmpty { continue }  // dummy element
			guard let axWin = axByWin[winNum] else { continue }
			let origin = AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &pt.origin)!
			let size = AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &pt.size)!
			// size→position→size→position: shrink first so AX doesn't clamp the new
			// origin against the current frame, then move, then re-apply the exact
			// size, and finally re-confirm the position in case size nudged it.
			AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, size)
			AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, origin)
			AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, size)
			AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, origin)
		}
	}
	
	private func axWinList(_ pid: pid_t) -> [AXUIElement] {
		let appRef = AXUIElementCreateApplication(pid)
		var value: CFTypeRef?
		AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
		if let windowList = value as? [AXUIElement] {
			var tmp: [AXUIElement] = []
			for win in windowList {
				var role: CFTypeRef?
				AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &role)
				if role as? String == kAXWindowRole {
					tmp.append(win)  // filter e.g. Finder's AXScrollArea
				}
			}
			return tmp
		}
		return []
	}

	// MARK: - Space Management -

	@objc func activeSpaceChanged(_ notification: Notification) {
		self.restoreState()
	}

	private func currentSpace() -> SpaceId? {
		let thisSpace = self.getWinIds()
		var candidates = self.spacesAll.filter { thisSpace.contains($0) }
		if candidates.count > 0 {
			let best = candidates.removeFirst()
			if candidates.count > 0 {
				// if a full-screen app is closed, win moves to current active space -> remove duplicates
				self.spacesAll.removeAll { candidates.contains($0) }
				for oldNum in candidates {
					NSApp.window(withWindowNumber: oldNum)?.close()
				}
			}
			return best
		}
		// create new space-id window (space was not visited yet)
		let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		win.isReleasedWhenClosed = false  // win is released either way. But crashes if true.
		guard win.isOnActiveSpace else {
			// dashboard or other full-screen app that prohibits display
			return nil
		}
		win.collectionBehavior = [.ignoresCycle, .stationary]
		win.setIsVisible(true)
		self.spacesAll.append(win.windowNumber)
		return win.windowNumber
	}
}

// MARK: - Status Bar Icon -

extension NSImage {
	static var statusIconDots: NSImage {
		let img = NSImage.init(size: .init(width: 20, height: 20), flipped: true) {
			let ctx = NSGraphicsContext.current!.cgContext
			let w = $0.width
			let h = $0.height
			let sw = 0.025 * w  // stroke width
			ctx.stroke(CGRect(x: 0.0 * w, y: 0.15 * h, width: 1.0 * w, height: 0.7 * h).insetBy(dx: sw / 2, dy: sw / 2), width: sw)
			ctx.fill(CGRect(x: 0, y: 0.55 * h, width: w, height: sw))
			let circle = CGRect(x: 0, y: 0.25 * h, width: 0.2 * w, height: 0.2 * w)
			ctx.fillEllipse(in: circle.offsetBy(dx: 0.12 * w, dy: 0))
			ctx.fillEllipse(in: circle.offsetBy(dx: 0.4 * w, dy: 0))
			ctx.fillEllipse(in: circle.offsetBy(dx: 0.68 * w, dy: 0))
			return true
		}
		img.isTemplate = true
		return img
	}

	static var statusIconMonitor: NSImage {
		let img = NSImage.init(size: .init(width: 21, height: 14), flipped: true) {
			let ctx = NSGraphicsContext.current!.cgContext
			let w = $0.width
			let h = $0.height
			let ssw = 0.025 * w  // small stroke width
			let lsw = 0.05 * w  // large stroke width
			// main screen
			ctx.stroke(CGRect(x: 0.1 * w, y: 0.0 * h, width: 0.8 * w, height: 0.8 * h).insetBy(dx: lsw / 2, dy: lsw / 2), width: lsw)
			ctx.clear(CGRect(x: 0.0 * w, y: 0.2 * h, width: 1.0 * w, height: 0.4 * h))
			ctx.fill(CGRect(x: 0.41 * w, y: 0.8 * h, width: 0.18 * w, height: 0.12 * h))
			ctx.fill(CGRect(x: 0.27 * w, y: 0.92 * h, width: 0.46 * w, height: 0.08 * h))
			// three windows
			ctx.stroke(CGRect(x: 0.0 * w, y: 0.28 * h, width: 0.27 * w, height: 0.24 * h).insetBy(dx: ssw / 2, dy: ssw / 2), width: ssw)
			ctx.stroke(CGRect(x: 0.34 * w, y: 0.2 * h, width: 0.32 * w, height: 0.4 * h).insetBy(dx: ssw / 2, dy: ssw / 2), width: ssw)
			ctx.stroke(CGRect(x: 0.73 * w, y: 0.28 * h, width: 0.27 * w, height: 0.24 * h).insetBy(dx: ssw / 2, dy: ssw / 2), width: ssw)
			return true
		}
		img.isTemplate = true
		return img
	}
}

// MARK: - Main Entry

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
