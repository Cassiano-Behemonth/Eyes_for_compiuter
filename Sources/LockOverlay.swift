import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

/// Janela sem borda que cobre a tela inteira e recebe o teclado.
final class LockWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) { keyHandler?(event) }
    // Engole atalhos com ⌘ (⌘Q, ⌘W, ⌘H…)
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

/// A tela de bloqueio: um olho por monitor, senha do macOS para sair.
final class LockOverlay {
    var onUnlock: (() -> Void)?

    private let safeMode: Bool
    private var windows: [LockWindow] = []
    private var eyes: [EyeView] = []
    private var password = ""
    private var verifying = false
    private var lastKey = Date()
    private var clearTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var unlocking = false
    private var touchContext: LAContext?
    private var touchView: LAAuthenticationView?

    init(safeMode: Bool) {
        self.safeMode = safeMode
    }

    func show() {
        // Precisa continuar como agente (sem ícone no Dock): o macOS só deixa janelas de apps
        // agente entrarem no Space de outro app em tela cheia (vídeo, apresentação…).
        // A prévia pode ter deixado o app como .regular.
        NSApp.setActivationPolicy(.accessory)
        buildWindows()

        var options: NSApplication.PresentationOptions = [
            .hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication,
            .disableAppleMenu, .disableSessionTermination,
        ]
        if !safeMode { options.insert(.disableForceQuit) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = options
        focus()
        NSCursor.hide()
        startTouchID()
        // Depois de cobrir a tela: carregar o MediaRemote não pode atrasar o bloqueio.
        DispatchQueue.main.async { Self.pauseMedia() }

        // Se outro app roubar o foco, pega de volta.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.focus() }
        })
        // Monitor plugado/desplugado: refaz as janelas.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.buildWindows()
            self?.focus()
            self?.startTouchID()
        })

        clearTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.password.isEmpty, Date().timeIntervalSince(self.lastKey) > 15 else { return }
            self.password = ""
            self.eyes.forEach { $0.eye.setPassword(length: 0) }
        }
    }

    /// Atualiza para onde os olhos olham. `point` em -1...1, nil = ninguém.
    func track(_ point: CGPoint?, closeness: CGFloat) {
        for view in eyes {
            view.eye.target = point
            view.eye.closeness = closeness
        }
    }

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        eyes.forEach { $0.stop() }
        windows = []
        eyes = []

        for screen in NSScreen.screens {
            let window = LockWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.keyHandler = { [weak self] event in self?.handleKey(event) }

            let view = EyeView(frame: NSRect(origin: .zero, size: screen.frame.size))
            if Self.touchIDAvailable { view.eye.hintText = "digite sua senha ou use a digital" }
            window.contentView = view
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                window.animator().alphaValue = 1
            }
            windows.append(window)
            eyes.append(view)
        }
    }

    private func focus() {
        NSApp.activate(ignoringOtherApps: true)
        let main = windows.first { $0.screen == NSScreen.main } ?? windows.first
        main?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Senha

    private func handleKey(_ event: NSEvent) {
        guard !verifying, !unlocking else { return }
        lastKey = Date()

        switch event.keyCode {
        case 36, 76: // return, enter
            submit()
            return
        case 51: // delete
            if !password.isEmpty { password.removeLast() }
        case 53: // esc
            password = ""
        default:
            let typed = (event.characters ?? "").filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 } }
            if password.count < 256 { password += typed }
        }
        eyes.forEach { $0.eye.setPassword(length: password.count) }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        verifying = true
        let attempt = password
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Auth.verify(attempt)
            DispatchQueue.main.async {
                self.verifying = false
                guard !self.unlocking else { return }
                self.password = ""
                if ok {
                    self.unlock()
                } else {
                    self.eyes.forEach {
                        $0.eye.anger()
                        $0.eye.setPassword(length: 0, shake: true)
                    }
                }
            }
        }
    }

    // MARK: - Touch ID

    private static var touchIDAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Fica esperando a digital enquanto a tela estiver bloqueada. O LAAuthenticationView
    /// substitui o diálogo do sistema, que ficaria escondido atrás das nossas janelas.
    private func startTouchID() {
        stopTouchID()
        guard !unlocking else { return }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
              let host = (windows.first { $0.screen == NSScreen.main } ?? windows.first)?.contentView
        else { return }

        let view = LAAuthenticationView(context: context, controlSize: .small)
        let side: CGFloat = 22
        view.frame = NSRect(x: (host.bounds.width - side) / 2, y: host.bounds.height * 0.17, width: side, height: side)
        host.addSubview(view)
        touchContext = context
        touchView = view

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "desbloquear o Eye") { ok, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.touchContext === context, !self.unlocking else { return }
                if ok {
                    self.unlock()
                    return
                }
                switch (error as? LAError)?.code {
                case .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled:
                    // Só a senha resolve agora.
                    self.stopTouchID()
                    return
                case .authenticationFailed:
                    self.eyes.forEach { $0.eye.anger() }
                default:
                    break
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.touchContext === context else { return }
                    self.startTouchID()
                }
            }
        }
    }

    private func stopTouchID() {
        let context = touchContext
        touchContext = nil
        context?.invalidate()
        touchView?.removeFromSuperview()
        touchView = nil
    }

    private func unlock() {
        unlocking = true
        stopTouchID()
        eyes.forEach { $0.eye.setPassword(length: 0) }
        let group = DispatchGroup()
        for view in eyes {
            group.enter()
            view.eye.close { group.leave() }
        }
        group.notify(queue: .main) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                self.windows.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                self.teardown()
                self.onUnlock?()
            })
        }
    }

    private func teardown() {
        stopTouchID()
        clearTimer?.invalidate()
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers = []
        eyes.forEach { $0.stop() }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        eyes = []
        NSApp.presentationOptions = []
        NSCursor.unhide()
    }

    /// Pausa o que estiver tocando (vídeo no navegador, Música, Spotify…) pelo MediaRemote,
    /// o mesmo caminho da tecla ⏯. É "pausar", não "alternar": não liga nada que estava parado.
    private static func pauseMedia() {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault,
                                          URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL),
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return }
        typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
        let send = unsafeBitCast(ptr, to: SendCommand.self)
        _ = send(1, nil)  // kMRPause
    }
}
