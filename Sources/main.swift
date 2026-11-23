import Carbon.HIToolbox
import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let modeItem = NSMenuItem(title: "External Only Mode", action: #selector(toggleMode), keyEquivalent: "l")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let iconOn = NSImage(systemSymbolName: "laptopcomputer.slash", accessibilityDescription: "Built-in display off")
    private let iconOff = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Built-in display on")
    private var signalSources: [DispatchSourceSignal] = []
    private var hotKey: EventHotKeyRef?
    private var refreshQueued = false

    /// What the user asked for. The actual display state is reconciled toward it.
    private var externalOnly = UserDefaults.standard.bool(forKey: "externalOnly") {
        didSet {
            UserDefaults.standard.set(externalOnly, forKey: "externalOnly")
            refresh()
        }
    }

    /// The built-in display's ID, kept so it can be re-enabled after it drops out of the online list.
    private var builtinID = CGDirectDisplayID(UserDefaults.standard.object(forKey: "builtinID") as? Int ?? 1) {
        didSet {
            if builtinID != oldValue { UserDefaults.standard.set(Int(builtinID), forKey: "builtinID") }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Display.isSupported else {
            let alert = NSAlert()
            alert.messageText = "Lidless can’t control displays on this version of macOS."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        buildMenu()
        observeDisplayChanges()
        terminateOnSignals()
        registerHotKey()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Display.Snapshot.current().builtin == nil {
            Display.set(builtinID, enabled: true)
        }
    }

    // MARK: State

    /// The built-in display is off only while the mode is on and an external display is connected.
    private func refresh() {
        let displays = Display.Snapshot.current()
        if let builtin = displays.builtin { builtinID = builtin }

        let shouldBeOff = externalOnly && !displays.externals.isEmpty
        let isOff = displays.builtin == nil
        if shouldBeOff != isOff {
            Display.set(builtinID, enabled: !shouldBeOff)
        }

        statusItem.button?.image = shouldBeOff ? iconOn : iconOff
        modeItem.state = externalOnly ? .on : .off
        modeItem.title = externalOnly && displays.externals.isEmpty
            ? "External Only Mode (waiting for a display)"
            : "External Only Mode"
    }

    /// Display changes arrive in bursts, so collapse each burst into one refresh.
    private func scheduleRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async {
            self.refreshQueued = false
            self.refresh()
        }
    }

    // MARK: Menu

    private func buildMenu() {
        modeItem.target = self
        modeItem.keyEquivalentModifierMask = [.control, .option, .command]
        loginItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(modeItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lidless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleMode() {
        externalOnly.toggle()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: System events

    private func observeDisplayChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().scheduleRefresh()
        }, context)

        // Waking with the lid open can bring the built-in display back.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
    }

    /// Route SIGTERM and friends through a normal quit, so the built-in display is restored.
    private func terminateOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Global ⌃⌥⌘L. Carbon hot keys need no Accessibility permission.
    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().toggleMode()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x4C49_444C), id: 1) // "LIDL"
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
