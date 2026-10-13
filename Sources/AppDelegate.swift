import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = Settings()
    private let detector = PresenceDetector()
    private var overlay: LockOverlay?
    private var previewWindow: NSWindow?
    private var previewEye: EyeView?

    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem?
    private var timer: Timer?

    private var lastSeen = Date()
    private var lastFrame = Date.distantPast
    private var cameraError: String?
    private var systemLocked = false
    /// Impede o App Nap de atrasar a câmera e os timers enquanto o Eye fica só na barra de menus.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Vigiando a câmera")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        detector.onFrame = { [weak self] s in self?.handle(s) }
        detector.onError = { [weak self] msg in
            self?.cameraError = msg
            self?.updateIcon()
        }
        // Câmera caiu e outra assumiu (ou a escolhida voltou): recomeça a contagem de ausência.
        detector.onSwitch = { [weak self] _ in self?.lastSeen = Date() }
        detector.start(cameraID: settings.cameraID)

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        observeSystem()

        // Deixa o olho de cada monitor desenhado para o bloqueio aparecer na hora.
        DragonEye.prepare(screens: NSScreen.screens)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            DragonEye.prepare(screens: NSScreen.screens)
        }

        let args = CommandLine.arguments
        if args.contains("--preview") { showPreview() }
        if args.contains("--lock") { lock() }
    }

    // MARK: - Presença

    private func handle(_ sighting: Sighting?) {
        let now = Date()
        lastFrame = now
        if cameraError != nil {
            cameraError = nil
            updateIcon()
        }
        // Só rosto conta como presença; corpo sem rosto serve só pro olho acompanhar.
        if sighting?.isFace == true { lastSeen = now }

        var point: CGPoint?
        var closeness: CGFloat = 0
        if let s = sighting {
            let x = settings.mirror ? 1 - s.point.x : s.point.x
            point = CGPoint(x: min(max((x - 0.5) * 2.4, -1), 1),
                            y: min(max((s.point.y - 0.55) * 2.4, -1), 1))
            closeness = min(max((s.size - 0.12) / 0.3, 0), 1)
        }
        overlay?.track(point, closeness: closeness)
        previewEye?.eye.target = point
        previewEye?.eye.closeness = closeness
        // Confere já, sem esperar o próximo tique do timer.
        evaluate()
    }

    private var cameraLive: Bool { Date().timeIntervalSince(lastFrame) < 2 }
    private var absentFor: TimeInterval { Date().timeIntervalSince(lastSeen) }

    private func evaluate() {
        statusLine?.title = statusText()
        guard overlay == nil, settings.enabled, !systemLocked, Auth.isAvailable else { return }
        // Sem imagem (tampa fechada, câmera ocupada…) nunca bloqueia; recomeça a contagem quando voltar.
        guard cameraLive else {
            lastSeen = Date()
            return
        }
        if absentFor >= settings.absenceDelay { lock() }
    }

    private func statusText() -> String {
        if let cameraError { return cameraError }
        if !Auth.isAvailable { return "Não achei seu usuário para conferir a senha" }
        if overlay != nil { return "Bloqueado — o dragão está de olho" }
        if !settings.enabled { return "Pausado" }
        if systemLocked { return "Mac bloqueado" }
        if !cameraLive { return "Esperando imagem da câmera…" }
        let absent = absentFor
        if absent < 0.6 { return "Você está aí" }
        return String(format: "Ninguém há %.0fs — bloqueia em %.0fs", absent, max(0, settings.absenceDelay - absent))
    }

    private func updateIcon() {
        let name: String
        if cameraError != nil {
            name = "eye.trianglebadge.exclamationmark"
        } else if !settings.enabled {
            name = "eye.slash"
        } else {
            name = overlay != nil ? "eye.fill" : "eye"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Eye")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Bloqueio

    private func lock() {
        guard overlay == nil else { return }
        closePreview()
        let o = LockOverlay(safeMode: settings.safeMode)
        o.onUnlock = { [weak self] in
            self?.overlay = nil
            self?.lastSeen = Date()
            self?.updateIcon()
        }
        overlay = o
        o.show()
        updateIcon()
    }

    private func observeSystem() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.systemLocked = true
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.systemLocked = false
            self?.lastSeen = Date()
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.lastSeen = Date() }
        }
    }

    // MARK: - Prévia

    private func showPreview() {
        if let previewWindow {
            previewWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Eye — prévia"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let view = EyeView(frame: window.contentLayoutRect)
        window.contentView = view
        window.center()
        previewWindow = window
        previewEye = view
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePreview() {
        previewWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === previewWindow else { return }
        previewEye?.stop()
        previewEye = nil
        previewWindow = nil
        if overlay == nil { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let line = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        line.isEnabled = false
        menu.addItem(line)
        statusLine = line
        menu.addItem(.separator())

        menu.addItem(MenuItem("Vigiar", checked: settings.enabled) { [weak self] in
            guard let self else { return }
            self.settings.enabled.toggle()
            self.lastSeen = Date()
            self.updateIcon()
        })
        menu.addItem(MenuItem("Bloquear agora", key: "l") { [weak self] in self?.lock() })
        menu.addItem(MenuItem("Mostrar o olho (prévia)", key: "p") { [weak self] in self?.showPreview() })
        menu.addItem(.separator())

        let delays: [(String, Double)] = [("1 segundo", 1), ("2 segundos", 2), ("5 segundos", 5), ("15 segundos", 15), ("30 segundos", 30),
                                          ("1 minuto", 60), ("2 minutos", 120), ("5 minutos", 300)]
        let delayMenu = NSMenu()
        for (title, value) in delays {
            delayMenu.addItem(MenuItem(title, checked: settings.absenceDelay == value) { [weak self] in
                self?.settings.absenceDelay = value
            })
        }
        let delayItem = NSMenuItem(title: "Bloquear após ausência de", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        let cameraMenu = NSMenu()
        let cameras = PresenceDetector.cameras()
        let current = detector.activeID ?? settings.cameraID ?? cameras.first { $0.deviceType == .builtInWideAngleCamera }?.uniqueID
        for device in cameras {
            cameraMenu.addItem(MenuItem(device.localizedName, checked: device.uniqueID == current) { [weak self] in
                guard let self else { return }
                self.settings.cameraID = device.uniqueID
                self.lastSeen = Date()
                self.detector.start(cameraID: device.uniqueID)
            })
        }
        let cameraItem = NSMenuItem(title: "Câmera", action: nil, keyEquivalent: "")
        cameraItem.submenu = cameraMenu
        menu.addItem(cameraItem)

        menu.addItem(MenuItem("Espelhar câmera", checked: settings.mirror) { [weak self] in self?.settings.mirror.toggle() })
        menu.addItem(MenuItem("Modo teste (⌥⌘⎋ funciona bloqueado)", checked: settings.safeMode) { [weak self] in
            self?.settings.safeMode.toggle()
        })
        let loginEnabled = SMAppService.mainApp.status == .enabled
        menu.addItem(MenuItem("Abrir ao iniciar sessão", checked: loginEnabled) {
            if loginEnabled {
                try? SMAppService.mainApp.unregister()
            } else {
                try? SMAppService.mainApp.register()
            }
        })
        menu.addItem(.separator())
        menu.addItem(MenuItem("Sair do Eye", key: "q") { NSApp.terminate(nil) })
    }

    func menuDidClose(_ menu: NSMenu) {
        statusLine = nil
    }
}

/// NSMenuItem com closure.
final class MenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
