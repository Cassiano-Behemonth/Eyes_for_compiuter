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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure(cameraID: cameraID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configure(cameraID: cameraID)
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

    private func configure(cameraID: String?) {
        let cameras = Self.cameras()
        let device = cameras.first { $0.uniqueID == cameraID }
            ?? cameras.first { $0.deviceType == .builtInWideAngleCamera }
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            onError?("Nenhuma câmera encontrada")
            return
        }

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

        DispatchQueue.main.async { self.onFrame?(sighting) }
    }
}
