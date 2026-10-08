import AppKit

// Texturas estáticas do olho, geradas uma vez com Core Graphics.
// Tudo que se move (íris, pupila, pálpebras) fica em camadas no DragonEye.

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }

    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + (hi - lo) * next() }
}

enum Art {
    /// Contorno amendoado do olho. openness 0 = fechado, 1 = aberto.
    static func almond(center: CGPoint, a: CGFloat, b: CGFloat, openness o: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let left = CGPoint(x: center.x - a, y: center.y - b * 0.1)
        let right = CGPoint(x: center.x + a, y: center.y + b * 0.08)
        let up = b * 1.36 * o
        let down = b * 1.28 * o
        p.move(to: left)
        p.addCurve(to: right,
                   control1: CGPoint(x: center.x - a * 0.5, y: center.y + up),
                   control2: CGPoint(x: center.x + a * 0.45, y: center.y + up * 1.02))
        p.addCurve(to: left,
                   control1: CGPoint(x: center.x + a * 0.5, y: center.y - down),
                   control2: CGPoint(x: center.x - a * 0.45, y: center.y - down))
        p.closeSubpath()
        return p
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func canvas(_ size: CGSize, _ scale: CGFloat) -> CGContext {
        let ctx = CGContext(data: nil,
                            width: max(1, Int(ceil(size.width * scale))),
                            height: max(1, Int(ceil(size.height * scale))),
                            bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineCap(.round)
        return ctx
    }

    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    }

    private static func polar(_ c: CGPoint, _ r: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
    }

    // MARK: - Íris

    static func iris(radius R: CGFloat, scale: CGFloat) -> CGImage {
        let ctx = canvas(CGSize(width: R * 2, height: R * 2), scale)
        let c = CGPoint(x: R, y: R)
        var rng = SeededRandom(seed: 7)

        ctx.addEllipse(in: CGRect(x: 0, y: 0, width: R * 2, height: R * 2))
        ctx.clip()

        ctx.drawRadialGradient(
            gradient([rgb(0xfff1a8), rgb(0xffc23a), rgb(0xff7a0a), rgb(0xe02a00), rgb(0x8a0700), rgb(0x2a0000)],
                     [0, 0.14, 0.32, 0.55, 0.8, 1]),
            startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [])

        // Fibras radiais
        for _ in 0..<1600 {
            let angle = rng.range(0, .pi * 2)
            let r0 = R * rng.range(0.08, 0.45)
            let r1 = R * rng.range(0.55, 1.0)
            let wobble = rng.range(-0.09, 0.09)
            let pick = rng.next()
            let color: CGColor
            if pick < 0.4 {
                color = rgb(0xffd25a, rng.range(0.08, 0.3))
            } else if pick < 0.75 {
                color = rgb(0xff4a00, rng.range(0.1, 0.35))
            } else {
                color = rgb(0x3a0000, rng.range(0.2, 0.5))
            }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(rng.range(0.6, 2.4) * R / 300)
            ctx.move(to: polar(c, r0, angle))
            ctx.addQuadCurve(to: polar(c, r1, angle + wobble), control: polar(c, (r0 + r1) / 2, angle - wobble * 1.5))
            ctx.strokePath()
        }

        // Criptas escuras
        for _ in 0..<80 {
            let p = polar(c, R * rng.range(0.35, 0.8), rng.range(0, .pi * 2))
            let s = R * rng.range(0.015, 0.055)
            ctx.setFillColor(rgb(0x250000, rng.range(0.25, 0.5)))
            ctx.fillEllipse(in: CGRect(x: p.x - s, y: p.y - s * 0.7, width: s * 2, height: s * 1.4))
        }

        // Colarete ondulado
        let collarette = CGMutablePath()
        for i in 0...240 {
            let t = CGFloat(i) / 240 * .pi * 2
            let r = R * (0.4 + 0.025 * sin(t * 23) + 0.012 * sin(t * 7))
            i == 0 ? collarette.move(to: polar(c, r, t)) : collarette.addLine(to: polar(c, r, t))
        }
        ctx.addPath(collarette)
        ctx.setStrokeColor(rgb(0xffe08a, 0.35))
        ctx.setLineWidth(R * 0.014)
        ctx.strokePath()

        // Brilho interno perto da pupila
        ctx.drawRadialGradient(gradient([rgb(0xfff4c0, 0.55), rgb(0xfff4c0, 0)], [0, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: R * 0.32, options: [])

        // Anel límbico escuro
        ctx.drawRadialGradient(gradient([rgb(0x0a0000, 0), rgb(0x0a0000, 0.6), rgb(0x0a0000, 0.97)], [0, 0.6, 1]),
                               startCenter: c, startRadius: R * 0.8, endCenter: c, endRadius: R, options: [])

        return ctx.makeImage()!
    }

    // MARK: - Esclera (fundo do olho, com veias)

    static func sclera(size: CGSize, scale: CGFloat) -> CGImage {
        let ctx = canvas(size, scale)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        var rng = SeededRandom(seed: 99)

        ctx.drawRadialGradient(gradient([rgb(0x6e1402), rgb(0x3a0500), rgb(0x120100)], [0, 0.55, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2,
                               options: [.drawsAfterEndLocation])

        for _ in 0..<44 {
            let fromLeft = rng.next() < 0.5
            var p = CGPoint(x: fromLeft ? rng.range(0, size.width * 0.12) : rng.range(size.width * 0.88, size.width),
                            y: rng.range(size.height * 0.2, size.height * 0.8))
            var heading: CGFloat = atan2(c.y - p.y, c.x - p.x) + rng.range(-0.6, 0.6)
            let steps = Int(rng.range(10, 26))
            var width = size.width * rng.range(0.002, 0.005)
            for _ in 0..<steps {
                heading += rng.range(-0.45, 0.45)
                let next = polar(p, size.width * 0.012, heading)
                ctx.setStrokeColor(rgb(0x2a0000, 0.55))
                ctx.setLineWidth(width)
                ctx.move(to: p)
                ctx.addLine(to: next)
                ctx.strokePath()
                p = next
                width *= 0.92
            }
        }
        return ctx.makeImage()!
    }

    // MARK: - Pele com escamas

    static func skin(size: CGSize, scale: CGFloat, eyeCenter: CGPoint, a: CGFloat, b: CGFloat) -> CGImage {
        let ctx = canvas(size, scale)
        var rng = SeededRandom(seed: 1234)

        ctx.setFillColor(rgb(0x070101))
        ctx.fill(CGRect(origin: .zero, size: size))

        func light(at p: CGPoint) -> CGFloat {
            let dx = (p.x - eyeCenter.x) / (a * 1.5)
            let dy = (p.y - eyeCenter.y) / (a * 0.95)
            return exp(-(dx * dx + dy * dy))
        }

        func shade(_ base: (CGFloat, CGFloat, CGFloat), _ k: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: min(1, base.0 * k), green: min(1, base.1 * k), blue: min(1, base.2 * k), alpha: alpha)
        }

        // Escamas pequenas em fileiras (de baixo pra cima, para as de cima cobrirem as de baixo)
        let sw = a * 0.13
        let rowH = sw * 0.42
        var row = 0
        var y = -sw
        while y < size.height + sw {
            var x = (row % 2 == 0 ? 0 : sw / 2) - sw
            while x < size.width + sw {
                let jx = x + rng.range(-sw * 0.04, sw * 0.04)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: jx - sw / 2, y: y + sw * 0.8))
                path.addLine(to: CGPoint(x: jx - sw / 2, y: y + sw * 0.35))
                path.addQuadCurve(to: CGPoint(x: jx, y: y), control: CGPoint(x: jx - sw / 2, y: y + sw * 0.02))
                path.addQuadCurve(to: CGPoint(x: jx + sw / 2, y: y + sw * 0.35), control: CGPoint(x: jx + sw / 2, y: y + sw * 0.02))
                path.addLine(to: CGPoint(x: jx + sw / 2, y: y + sw * 0.8))
                path.closeSubpath()

                let l = light(at: CGPoint(x: jx, y: y + sw * 0.3)) * rng.range(0.75, 1.15)
                let base: (CGFloat, CGFloat, CGFloat) = (0.05 + 0.33 * l, 0.012 + 0.09 * l, 0.008 + 0.04 * l)

                // sombra que a escama projeta na de baixo
                ctx.saveGState()
                ctx.translateBy(x: 0, y: -sw * 0.05)
                ctx.addPath(path)
                ctx.setFillColor(rgb(0x000000, 0.6))
                ctx.fillPath()
                ctx.restoreGState()

                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                ctx.drawLinearGradient(gradient([shade(base, 0.45), shade(base, 1.0)], [0, 1]),
                                       start: CGPoint(x: jx, y: y + sw * 0.8), end: CGPoint(x: jx, y: y + sw * 0.1), options: [])
                ctx.restoreGState()

                // borda inferior iluminada
                let edge = CGMutablePath()
                edge.move(to: CGPoint(x: jx - sw / 2, y: y + sw * 0.35))
                edge.addQuadCurve(to: CGPoint(x: jx, y: y), control: CGPoint(x: jx - sw / 2, y: y + sw * 0.02))
                edge.addQuadCurve(to: CGPoint(x: jx + sw / 2, y: y + sw * 0.35), control: CGPoint(x: jx + sw / 2, y: y + sw * 0.02))
                ctx.addPath(edge)
                ctx.setStrokeColor(shade(base, 1.7, 0.8))
                ctx.setLineWidth(sw * 0.03)
                ctx.strokePath()

                x += sw
            }
            y += rowH
            row += 1
        }

        // Pele das pálpebras (aparece quando o olho fecha/pisca)
        let lidOuter = almond(center: eyeCenter, a: a, b: b, openness: 1.0)
        ctx.saveGState()
        ctx.addPath(lidOuter)
        ctx.addPath(lidOuter.copy(strokingWithWidth: b * 0.5, lineCap: .round, lineJoin: .round, miterLimit: 10))
        ctx.clip(using: .winding)
        ctx.drawRadialGradient(gradient([rgb(0x4a1209), rgb(0x2a0805), rgb(0x0e0201)], [0, 0.6, 1]),
                               startCenter: CGPoint(x: eyeCenter.x, y: eyeCenter.y - b * 0.1), startRadius: 0,
                               endCenter: CGPoint(x: eyeCenter.x, y: eyeCenter.y - b * 0.1), endRadius: a * 1.1, options: [.drawsAfterEndLocation])
        // grânulos
        for _ in 0..<Int(a * 1.4) {
            let x = eyeCenter.x + rng.range(-a * 1.1, a * 1.1)
            let y = eyeCenter.y + rng.range(-b * 1.5, b * 1.5)
            let r = b * rng.range(0.015, 0.04)
            ctx.setFillColor(rng.next() < 0.5 ? rgb(0x000000, 0.35) : rgb(0x7a2410, 0.18))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 1.6))
        }
        // vincos acompanhando o formato do olho
        for o in stride(from: CGFloat(0.12), through: 1.0, by: 0.11) {
            ctx.addPath(almond(center: eyeCenter, a: a * (1 - 0.04 * o), b: b, openness: o))
            ctx.setStrokeColor(rgb(0x000000, 0.45))
            ctx.setLineWidth(b * 0.022)
            ctx.strokePath()
            ctx.addPath(almond(center: CGPoint(x: eyeCenter.x, y: eyeCenter.y - b * 0.025), a: a * (1 - 0.04 * o), b: b, openness: o))
            ctx.setStrokeColor(rgb(0x8a2a12, 0.18))
            ctx.setLineWidth(b * 0.012)
            ctx.strokePath()
        }
        // linha onde as pálpebras se encontram
        ctx.addPath(almond(center: eyeCenter, a: a, b: b, openness: 0.02))
        ctx.setStrokeColor(rgb(0x000000, 0.9))
        ctx.setLineWidth(b * 0.05)
        ctx.strokePath()
        ctx.restoreGState()

        // Anéis de escamas em volta do olho: pequenas perto da pálpebra, crescendo pra fora.
        // Desenha de fora pra dentro, pra as de dentro ficarem por cima.
        var sizes: [CGFloat] = []
        var offsets: [CGFloat] = []
        var acc: CGFloat = b * 0.12
        for k in 0..<9 {
            let s = a * 0.055 * (1 + 0.3 * CGFloat(k))
            sizes.append(s)
            offsets.append(acc + s * 0.5)
            acc += s * 0.78
        }
        for k in stride(from: sizes.count - 1, through: 0, by: -1) {
            let s = sizes[k]
            let rx = a * 1.0 + offsets[k] * 1.05
            let ry = b * 1.05 + offsets[k]
            let perimeter = CGFloat.pi * (3 * (rx + ry) - sqrt((3 * rx + ry) * (rx + 3 * ry)))
            let n = Int(perimeter / (s * 0.82))
            let phase = k % 2 == 0 ? 0 : CGFloat.pi / CGFloat(n)
            let ringLight = exp(-CGFloat(k) * 0.3)
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n) * .pi * 2 + phase + rng.range(-0.01, 0.01)
                let p = CGPoint(x: eyeCenter.x + cos(t) * rx, y: eyeCenter.y + sin(t) * ry)
                let normal = atan2(sin(t) * rx, cos(t) * ry)   // aponta pra fora da elipse
                let w = s * rng.range(0.95, 1.12)
                let h = s * rng.range(0.78, 0.92)
                // mais luz embaixo do olho (o brilho da íris ilumina a pálpebra de baixo)
                let l = ringLight * (0.75 + 0.25 * max(0, -sin(t))) * rng.range(0.8, 1.15)

                ctx.saveGState()
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: normal - .pi / 2)
                // local: +y = pra fora do olho, -y = virado pro olho
                let pebble = CGMutablePath()
                pebble.move(to: CGPoint(x: -w / 2, y: h * 0.1))
                pebble.addCurve(to: CGPoint(x: w / 2, y: h * 0.1),
                                control1: CGPoint(x: -w * 0.45, y: h * 0.75), control2: CGPoint(x: w * 0.45, y: h * 0.75))
                pebble.addCurve(to: CGPoint(x: -w / 2, y: h * 0.1),
                                control1: CGPoint(x: w * 0.5, y: -h * 0.65), control2: CGPoint(x: -w * 0.5, y: -h * 0.65))
                pebble.closeSubpath()

                ctx.setShadow(offset: .zero, blur: s * 0.35, color: rgb(0x000000, 0.95))
                ctx.addPath(pebble)
                ctx.setFillColor(rgb(0x0c0201))
                ctx.fillPath()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)

                ctx.addPath(pebble)
                ctx.clip()
                ctx.drawRadialGradient(
                    gradient([CGColor(srgbRed: 0.55 * l, green: 0.15 * l, blue: 0.06 * l, alpha: 1),
                              CGColor(srgbRed: 0.22 * l, green: 0.05 * l, blue: 0.025 * l, alpha: 1),
                              rgb(0x0a0201)], [0, 0.55, 1]),
                    startCenter: CGPoint(x: 0, y: -h * 0.35), startRadius: 0,
                    endCenter: CGPoint(x: 0, y: h * 0.1), endRadius: w * 0.75, options: [.drawsAfterEndLocation])
                ctx.restoreGState()
            }
        }

        // Vinheta
        let maxDim = max(size.width, size.height)
        ctx.drawRadialGradient(gradient([rgb(0x000000, 0), rgb(0x000000, 0.6), rgb(0x000000, 0.95)], [0, 0.6, 1]),
                               startCenter: eyeCenter, startRadius: a * 0.9, endCenter: eyeCenter, endRadius: maxDim * 0.75,
                               options: [.drawsAfterEndLocation])

        return ctx.makeImage()!
    }
}
