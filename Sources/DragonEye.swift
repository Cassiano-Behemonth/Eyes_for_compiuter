import AppKit
import QuartzCore

/// O olho do dragão: uma árvore de CALayers + um "step" chamado a cada frame.
final class DragonEye {
    let root = CALayer()

    /// Para onde olhar, em -1...1 (x: esquerda→direita, y: baixo→cima). nil = ninguém na câmera.
    var target: CGPoint?
    /// 0 = longe, 1 = bem perto da câmera.
    var closeness: CGFloat = 0

    /// Tudo que respira junto (olho e pele). Dica e pontinhos ficam fora, parados.
    private let body = CALayer()
    private let skin = CALayer()
    private let glow = CAGradientLayer()
    private let opening = CALayer()
    private let openingMask = CAShapeLayer()
    private let sclera = CALayer()
    private let irisGroup = CALayer()
    private let iris = CALayer()
    private let irisHeat = CAGradientLayer()
    private let pupil = CAShapeLayer()
    private let membrane = CAGradientLayer()
    private let upperShadow = CAGradientLayer()
    private let lowerShadow = CAGradientLayer()
    private let highlight = CAGradientLayer()
    private let highlightSmall = CAGradientLayer()
    private let rimOuter = CAShapeLayer()
    private let rimInner = CAShapeLayer()
    private let dots = CALayer()
    private let hint = CATextLayer()

    private var size = CGSize.zero
    private var scale: CGFloat = 0
    private var center = CGPoint.zero
    private var a: CGFloat = 0      // meia-largura do olho
    private var b: CGFloat = 0      // meia-altura do olho
    private var irisR: CGFloat = 0

    private var gaze = CGPoint.zero
    private var pupilWidth: CGFloat = 0.42
    private var openness: CGFloat = 0
    private var lastStep: CFTimeInterval?
    private var lastTargetTime: CFTimeInterval = 0
    private var hadTarget = false
    private var wander = CGPoint.zero
    private var nextWander: CFTimeInterval = 0
    private var blinkStart: CFTimeInterval?
    private var blinkMembrane = false
    private var nextBlink: CFTimeInterval = 0
    private var angerStart: CFTimeInterval = -100
    private var startle: CFTimeInterval = -100
    private var breathPhase: CGFloat = 0
    private var closeStart: CFTimeInterval?
    private var closeCompletion: (() -> Void)?
    private var rng = SeededRandom(seed: UInt64(Date().timeIntervalSince1970))

    init() {
        root.backgroundColor = rgb(0x000000)
        root.addSublayer(body)
        body.addSublayer(skin)
        body.addSublayer(glow)
        body.addSublayer(opening)
        opening.mask = openingMask
        opening.addSublayer(sclera)
        opening.addSublayer(irisGroup)
        irisGroup.addSublayer(iris)
        irisGroup.addSublayer(irisHeat)
        irisGroup.addSublayer(pupil)
        opening.addSublayer(membrane)
        opening.addSublayer(upperShadow)
        opening.addSublayer(lowerShadow)
        opening.addSublayer(highlight)
        opening.addSublayer(highlightSmall)
        body.addSublayer(rimInner)
        body.addSublayer(rimOuter)
        root.addSublayer(dots)
        root.addSublayer(hint)

        glow.type = .radial
        glow.colors = [rgb(0xff4a00, 0.45), rgb(0xff2200, 0.12), rgb(0xff2200, 0)]
        glow.locations = [0, 0.45, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)

        irisHeat.type = .radial
        irisHeat.colors = [rgb(0xfff2b0, 0.9), rgb(0xff7a10, 0.55), rgb(0xff3000, 0)]
        irisHeat.startPoint = CGPoint(x: 0.5, y: 0.5)
        irisHeat.endPoint = CGPoint(x: 1, y: 1)
        irisHeat.opacity = 0

        pupil.fillColor = rgb(0x040000)
        pupil.shadowColor = rgb(0x000000)
        pupil.shadowOpacity = 0.9
        pupil.shadowOffset = .zero

        membrane.colors = [rgb(0xffc8b0, 0.15), rgb(0xd9806a, 0.42), rgb(0xffe0d0, 0.6)]
        membrane.locations = [0, 0.85, 1]
        membrane.startPoint = CGPoint(x: 0, y: 0.5)
        membrane.endPoint = CGPoint(x: 1, y: 0.5)
        membrane.isHidden = true

        upperShadow.colors = [rgb(0x000000, 0.88), rgb(0x000000, 0)]
        upperShadow.locations = [0, 0.45]
        upperShadow.startPoint = CGPoint(x: 0.5, y: 1)
        upperShadow.endPoint = CGPoint(x: 0.5, y: 0)

        lowerShadow.colors = [rgb(0x000000, 0.6), rgb(0x000000, 0)]
        lowerShadow.locations = [0, 0.3]
        lowerShadow.startPoint = CGPoint(x: 0.5, y: 0)
        lowerShadow.endPoint = CGPoint(x: 0.5, y: 1)

        for h in [highlight, highlightSmall] {
            h.type = .radial
            h.startPoint = CGPoint(x: 0.5, y: 0.5)
            h.endPoint = CGPoint(x: 1, y: 1)
        }
        highlight.colors = [rgb(0xffffff, 0.4), rgb(0xffffff, 0)]
        highlightSmall.colors = [rgb(0xffffff, 0.95), rgb(0xffffff, 0)]

        rimOuter.fillColor = nil
        rimOuter.strokeColor = rgb(0x050000)
        rimOuter.lineJoin = .round
        rimInner.fillColor = nil
        rimInner.strokeColor = rgb(0x2a0804)
        rimInner.shadowColor = rgb(0x000000)
        rimInner.shadowOpacity = 0.6
        rimInner.shadowOffset = .zero
        rimInner.lineJoin = .round

        hint.string = "digite sua senha"
        hint.alignmentMode = .center
        hint.foregroundColor = rgb(0xff6a3a, 0.75)
        hint.opacity = 0
    }

    // MARK: - Layout

    func layout(size newSize: CGSize, scale newScale: CGFloat) {
        guard newSize.width > 0, newSize.height > 0, newSize != size || newScale != scale else { return }
        size = newSize
        scale = newScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        (a, b, irisR, center) = Self.geometry(size)
        let art = Self.art(size: size, scale: scale)

        func setScale(_ l: CALayer) {
            l.contentsScale = scale
            l.sublayers?.forEach(setScale)
        }
        setScale(root)
        openingMask.contentsScale = scale

        root.frame = CGRect(origin: .zero, size: size)
        body.setAffineTransform(.identity)
        body.frame = root.bounds
        skin.frame = root.bounds
        skin.contents = art.skin

        glow.frame = CGRect(x: center.x - a * 1.6, y: center.y - a * 1.0, width: a * 3.2, height: a * 2.0)

        opening.frame = root.bounds
        openingMask.frame = root.bounds

        let eyeBox = CGRect(x: center.x - a, y: center.y - b * 1.4, width: a * 2, height: b * 2.8)
        sclera.frame = eyeBox
        sclera.contents = art.sclera
        upperShadow.frame = eyeBox
        lowerShadow.frame = eyeBox

        irisGroup.bounds = CGRect(x: 0, y: 0, width: irisR * 2, height: irisR * 2)
        irisGroup.position = center
        iris.contents = art.iris
        pupil.shadowRadius = irisR * 0.06

        highlight.frame = CGRect(x: center.x - a * 0.5, y: center.y + b * 0.2, width: a * 0.42, height: b * 0.5)
        highlightSmall.frame = CGRect(x: center.x - a * 0.3, y: center.y + b * 0.42, width: a * 0.07, height: b * 0.12)

        rimOuter.lineWidth = b * 0.07
        rimInner.shadowRadius = b * 0.12
        rimInner.lineWidth = b * 0.24

        hint.fontSize = max(13, size.height * 0.018)
        hint.frame = CGRect(x: 0, y: size.height * 0.07, width: size.width, height: hint.fontSize * 1.5)
        dots.frame = CGRect(x: 0, y: size.height * 0.11, width: size.width, height: size.height * 0.03)

        step(now: CACurrentMediaTime())
    }

    private static func geometry(_ size: CGSize) -> (a: CGFloat, b: CGFloat, irisR: CGFloat, center: CGPoint) {
        let a = min(size.width * 0.36, size.height * 0.6)
        let b = a * 0.4
        return (a, b, b * 1.32, CGPoint(x: size.width / 2, y: size.height * 0.52))
    }

    // MARK: - Imagens prontas

    /// Desenhar pele, esclera e íris leva quase 1s numa tela Retina; o bloqueio não pode esperar isso.
    /// `prepare` desenha antes (em segundo plano) e a tela de bloqueio só reaproveita.
    private struct ArtSet {
        let skin: CGImage
        let sclera: CGImage
        let iris: CGImage
    }

    private struct ArtKey: Hashable {
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat
    }

    private static let artLock = NSLock()
    private static var artCache: [ArtKey: ArtSet] = [:]

    private static func art(size: CGSize, scale: CGFloat) -> ArtSet {
        let key = ArtKey(width: size.width, height: size.height, scale: scale)
        artLock.lock()
        let cached = artCache[key]
        artLock.unlock()
        if let cached { return cached }

        let (a, b, irisR, center) = geometry(size)
        let set = ArtSet(skin: Art.skin(size: size, scale: scale, eyeCenter: center, a: a, b: b),
                         sclera: Art.sclera(size: CGSize(width: a * 2, height: b * 2.8), scale: scale),
                         iris: Art.iris(radius: irisR, scale: scale))
        artLock.lock()
        // A prévia redimensionável gera tamanhos novos a todo momento; não deixa acumular.
        if artCache.count >= 8 { artCache.removeAll() }
        artCache[key] = set
        artLock.unlock()
        return set
    }

    /// Desenha de antemão as imagens de um olho em tela cheia para cada monitor.
    static func prepare(screens: [NSScreen]) {
        let specs = screens.map { ($0.frame.size, $0.backingScaleFactor) }
        DispatchQueue.global(qos: .utility).async {
            for (size, scale) in specs { _ = art(size: size, scale: scale) }
        }
    }

    // MARK: - Ações

    /// Texto que aparece embaixo dos pontinhos.
    var hintText: String {
        get { hint.string as? String ?? "" }
        set { hint.string = newValue }
    }

    /// Raiva: senha errada.
    func anger() { angerStart = CACurrentMediaTime() }

    /// Fecha o olho devagar e chama completion no final.
    func close(completion: @escaping () -> Void) {
        closeStart = CACurrentMediaTime()
        closeCompletion = completion
    }

    /// Mostra os pontinhos da senha digitada.
    func setPassword(length: Int, shake: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dots.sublayers?.forEach { $0.removeFromSuperlayer() }
        let d = max(8, size.height * 0.011)
        let gap = d * 1.1
        let shown = min(length, 24)
        let total = CGFloat(shown) * d + CGFloat(max(0, shown - 1)) * gap
        var x = (dots.bounds.width - total) / 2
        for _ in 0..<shown {
            let dot = CALayer()
            dot.frame = CGRect(x: x, y: (dots.bounds.height - d) / 2, width: d, height: d)
            dot.cornerRadius = d / 2
            dot.backgroundColor = rgb(0xff5a2a)
            dot.shadowColor = rgb(0xff3000)
            dot.shadowOpacity = 0.9
            dot.shadowRadius = d * 0.6
            dot.shadowOffset = .zero
            dots.addSublayer(dot)
            x += d + gap
        }
        CATransaction.commit()

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = hint.presentation()?.opacity ?? hint.opacity
        hint.opacity = length > 0 || shake ? 1 : 0
        hint.add(anim, forKey: "fade")

        if shake {
            let s = CAKeyframeAnimation(keyPath: "position.x")
            let x0 = dots.position.x
            let amp = size.width * 0.01
            s.values = [x0, x0 - amp, x0 + amp, x0 - amp * 0.6, x0 + amp * 0.6, x0]
            s.duration = 0.4
            dots.add(s, forKey: "shake")
            hint.add(s, forKey: "shake")
        }
    }

    // MARK: - Frame

    /// Avança a simulação até `t` (normalmente CACurrentMediaTime()).
    func step(now t: CFTimeInterval) {
        guard a > 0 else { return }
        let dt = CGFloat(min(max(t - (lastStep ?? t), 0), 0.05))
        lastStep = t

        if target != nil {
            if !hadTarget { startle = t }
            hadTarget = true
            lastTargetTime = t
        } else {
            hadTarget = false
        }

        // Para onde olhar
        let desired: CGPoint
        if let tg = target {
            desired = tg
        } else {
            if t >= nextWander {
                wander = CGPoint(x: rng.range(-0.8, 0.8), y: rng.range(-0.5, 0.5))
                nextWander = t + Double(rng.range(1.2, 4.0))
            }
            desired = wander
        }
        let gk: CGFloat = target != nil ? 9 : 2.5
        gaze.x += (desired.x - gaze.x) * (1 - exp(-gk * dt))
        gaze.y += (desired.y - gaze.y) * (1 - exp(-gk * dt))

        let angerK = t - angerStart < 1.6 ? CGFloat(1 - (t - angerStart) / 1.6) : 0
        let startleK = t - startle < 0.6 ? CGFloat(1 - (t - startle) / 0.6) : 0

        // Pupila: contrai rápido, dilata devagar
        var desiredPupil: CGFloat = target != nil ? (0.16 - 0.08 * closeness) : 0.42
        if startleK > 0 { desiredPupil = 0.05 }
        if angerK > 0 { desiredPupil = 0.035 }
        let pk: CGFloat = desiredPupil < pupilWidth ? 10 : 2.5
        pupilWidth += (desiredPupil - pupilWidth) * (1 - exp(-pk * dt))

        // Abertura: sonolento quando ninguém aparece há um tempo, arregala no susto, aperta na raiva
        var desiredOpen: CGFloat = 1
        if target == nil && t - lastTargetTime > 20 { desiredOpen = 0.55 }
        if startleK > 0 { desiredOpen = 1.12 }
        if angerK > 0 { desiredOpen = 0.6 }
        let ok: CGFloat = desiredOpen > openness ? 5 : 2
        openness += (desiredOpen - openness) * (1 - exp(-ok * dt))

        // Piscadas (às vezes com a membrana nictitante, de lado)
        var lid: CGFloat = 1
        var membraneK: CGFloat = 0
        if blinkStart == nil, closeStart == nil, t >= nextBlink {
            blinkStart = t
            blinkMembrane = rng.next() < 0.45
            nextBlink = t + Double(rng.range(3.5, 9))
        }
        if let bs = blinkStart {
            let e = CGFloat(max(0, t - bs))
            if blinkMembrane {
                membraneK = e < 0.7 ? sin(.pi * e / 0.7) : 0
                if e >= 0.7 { blinkStart = nil }
            } else {
                if e < 0.11 { lid = 1 - e / 0.11 } else if e < 0.15 { lid = 0 } else if e < 0.36 { lid = (e - 0.15) / 0.21 }
                if e >= 0.36 { blinkStart = nil }
            }
        }
        if let cs = closeStart {
            let e = CGFloat(t - cs)
            lid = max(0, 1 - e / 0.8)
            if e >= 1.0, let done = closeCompletion {
                closeCompletion = nil
                done()
            }
        }
        let o = max(0, openness * min(max(lid, 0), 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let path = almond(o)
        openingMask.path = path
        rimOuter.path = path
        rimInner.path = path

        let maxX = a - irisR * 0.72
        let maxY = b * 0.32
        // Achata a íris quando olha pro lado (perspectiva). Sem transform, pra o snapshot funcionar igual.
        let irisBox = CGRect(x: 0, y: 0, width: irisR * 2 * (1 - 0.14 * abs(gaze.x)), height: irisR * 2)
        irisGroup.bounds = irisBox
        irisGroup.position = CGPoint(x: center.x + gaze.x * maxX, y: center.y + gaze.y * maxY)
        iris.frame = irisBox
        irisHeat.frame = irisBox
        pupil.frame = irisBox
        pupil.path = slit(in: irisBox, width: irisR * pupilWidth * 1.4, height: irisR * 1.72)

        // Respiração de fera: puxa o ar rápido, solta devagar. Acelera vigiando alguém, ofega com raiva.
        // A escala base maior que 1 esconde as bordas quando a imagem sobe.
        let period: CGFloat = angerK > 0 ? 1.3 : (target != nil ? 3.0 : 4.2)
        breathPhase = (breathPhase + dt / period).truncatingRemainder(dividingBy: 1)
        let bp = breathPhase
        let breath = bp < 0.35 ? -cos(.pi * bp / 0.35) : cos(.pi * (bp - 0.35) / 0.65)
        let amp = 1 + 0.6 * angerK
        body.setAffineTransform(CGAffineTransform(translationX: 0, y: size.height * 0.014 * breath * amp)
            .scaledBy(x: 1.045 + 0.013 * breath * amp, y: 1.045 + 0.013 * breath * amp))

        irisHeat.opacity = Float(max(angerK, startleK * 0.5))
        glow.opacity = Float(0.65 + 0.18 * breath + 0.35 * angerK)

        if membraneK > 0.001 {
            membrane.isHidden = false
            membrane.frame = CGRect(x: center.x - a, y: center.y - b * 1.4, width: a * 2 * membraneK, height: b * 2.8)
        } else {
            membrane.isHidden = true
        }

        CATransaction.commit()
    }

    /// Pula a animação de abertura e as piscadas (usado no snapshot).
    func settle(seconds: Double) {
        nextBlink = .infinity
        blinkStart = nil
        startle = -100
        hadTarget = target != nil
        var t: Double = 0
        lastStep = nil
        while t < seconds {
            step(now: t)
            t += 1.0 / 60
        }
        lastStep = nil
        nextBlink = CACurrentMediaTime() + 4
    }

    // MARK: - Formas

    private func almond(_ o: CGFloat) -> CGPath {
        Art.almond(center: center, a: a, b: b, openness: o)
    }

    private func slit(in box: CGRect, width w: CGFloat, height h: CGFloat) -> CGPath {
        let cx = box.midX, cy = box.midY
        let c = (w / 2) / 0.75
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx, y: cy + h / 2))
        p.addCurve(to: CGPoint(x: cx, y: cy - h / 2),
                   control1: CGPoint(x: cx + c, y: cy + h / 4), control2: CGPoint(x: cx + c, y: cy - h / 4))
        p.addCurve(to: CGPoint(x: cx, y: cy + h / 2),
                   control1: CGPoint(x: cx - c, y: cy - h / 4), control2: CGPoint(x: cx - c, y: cy + h / 4))
        p.closeSubpath()
        return p
    }
}
