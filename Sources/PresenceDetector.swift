import AVFoundation
import Vision

/// Alguém visto pela câmera. Coordenadas normalizadas 0...1, origem embaixo à esquerda,
/// na imagem crua da câmera (sem espelhar).
struct Sighting {
    var point: CGPoint
    /// Largura do rosto/corpo em relação à imagem (proxy de distância).
    var size: CGFloat
    var isFace: Bool
}

final class PresenceDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Chamado na main thread a cada análise (~10x/s). nil = ninguém.
    var onFrame: ((Sighting?) -> Void)?
    /// Chamado na main thread quando a câmera não pode ser usada.
    var onError: ((String) -> Void)?
    /// Chamado na main thread quando troca sozinho de câmera (nome da nova).
    var onSwitch: ((String) -> Void)?

    /// uniqueID da câmera em uso agora (main thread).
    private(set) var activeID: String?
    /// Câmera escolhida pelo usuário; volta pra ela quando reconectar.
    private var preferredID: String?
    private var observing = false
    /// Último quadro analisado (main thread); o watchdog religa a câmera se parar de chegar.
    private var lastFrame = CACurrentMediaTime()
    private var watchdog: Timer?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "eye.camera")
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let humanRequest: VNDetectHumanRectanglesRequest = {
        let r = VNDetectHumanRectanglesRequest()
        r.upperBodyOnly = true
        return r
    }()
    private var lastAnalysis: CFTimeInterval = 0
    private let interval: CFTimeInterval = 0.1

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    func start(cameraID: String?) {
        preferredID = cameraID
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configure()
                    } else {
                        self.onError?("Sem permissão para a câmera")
                    }
                }
            }
        default:
            onError?("Sem permissão para a câmera (Ajustes do Sistema › Privacidade › Câmera)")
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    /// Escolhe a preferida; se ela não estiver conectada, a embutida; senão qualquer outra.
    private func pickDevice(excluding excluded: String? = nil) -> AVCaptureDevice? {
        let cameras = Self.cameras().filter { $0.isConnected && $0.uniqueID != excluded }
        return cameras.first { $0.uniqueID == preferredID }
            ?? cameras.first { $0.deviceType == .builtInWideAngleCamera }
            ?? cameras.first
    }

    private func observeDevices() {
        guard !observing else { return }
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let device = n.object as? AVCaptureDevice, device.uniqueID == self.activeID else { return }
            self.activeID = nil
            self.configure(excluding: device.uniqueID, switching: true)
        }
        nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let device = n.object as? AVCaptureDevice, device.hasMediaType(.video) else { return }
            // Sem câmera nenhuma, ou a preferida voltou: troca pra ela.
            if self.activeID == nil || (device.uniqueID == self.preferredID && self.activeID != device.uniqueID) {
                self.configure(switching: true)
            }
        }
        nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
            // Erro na câmera em uso (ex.: travou ao ser puxada): reabre com a melhor câmera disponível.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.configure(switching: true) }
        }
        // A sessão também para sem avisar erro (Mac dormiu, tela bloqueada, outro app pegou a câmera,
        // câmera USB congelou). Se os quadros pararem de chegar, reabre a câmera.
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, CACurrentMediaTime() - self.lastFrame > 4 else { return }
            self.lastFrame = CACurrentMediaTime()  // espera mais 4s antes de tentar de novo
            self.configure()
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func configure(excluding excluded: String? = nil, switching: Bool = false) {
        observeDevices()
        guard let device = pickDevice(excluding: excluded) else {
            activeID = nil
            queue.async {
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.commitConfiguration()
            }
            onError?("Nenhuma câmera encontrada")
            return
        }
        if switching, device.uniqueID != activeID { onSwitch?(device.localizedName) }
        activeID = device.uniqueID

        queue.async {
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.onError?("Não consegui abrir a câmera: \(error.localizedDescription)") }
                return
            }
            if self.session.outputs.isEmpty {
                self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.output.alwaysDiscardsLateVideoFrames = true
                self.output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            }
            for preset in [AVCaptureSession.Preset.vga640x480, .medium, .low] where self.session.canSetSessionPreset(preset) {
                self.session.sessionPreset = preset
                break
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= interval, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now

        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([faceRequest, humanRequest])

        func area(_ o: VNDetectedObjectObservation) -> CGFloat { o.boundingBox.width * o.boundingBox.height }

        var sighting: Sighting?
        if let face = faceRequest.results?.filter({ $0.confidence > 0.5 }).max(by: { area($0) < area($1) }) {
            let box = face.boundingBox
            sighting = Sighting(point: CGPoint(x: box.midX, y: box.midY), size: box.width, isFace: true)
        } else if let body = humanRequest.results?.filter({ $0.confidence > 0.6 }).max(by: { area($0) < area($1) }) {
            // corpo sem rosto (de lado, passando): mira mais ou menos onde estaria a cabeça
            let box = body.boundingBox
            sighting = Sighting(point: CGPoint(x: box.midX, y: box.maxY - box.height * 0.2), size: box.width * 0.5, isFace: false)
        }

        DispatchQueue.main.async {
            self.lastFrame = CACurrentMediaTime()
            self.onFrame?(sighting)
        }
    }
}
