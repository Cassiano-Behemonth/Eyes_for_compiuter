import AppKit

/// `Eye --snapshot saida.png [x,y] [raiva]` renderiza o olho num PNG sem abrir janela (pra conferir a arte).
enum Snapshot {
    static func run(arguments: [String]) -> Int32 {
        guard let out = arguments.first else {
            print("uso: Eye --snapshot saida.png [x,y] [raiva]")
            return 1
        }
        let size = CGSize(width: 1600, height: 1000)
        let eye = DragonEye()
        eye.layout(size: size, scale: 1)
        if arguments.count > 1 {
            let parts = arguments[1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { eye.target = CGPoint(x: parts[0], y: parts[1]) }
        }
        eye.settle(seconds: 3)
        if arguments.count > 2 {
            eye.anger()
            let t0 = CACurrentMediaTime()
            for i in 0..<30 { eye.step(now: t0 + Double(i) / 60) }
        }

        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        eye.root.render(in: ctx)
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)
        else { return 1 }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? 0 : 1
    }

    /// `Eye --icon saida.png`: ícone 1024×1024 no formato do macOS (quadrado arredondado com sombra).
    static func icon(arguments: [String]) -> Int32 {
        guard let out = arguments.first else {
            print("uso: Eye --icon saida.png")
            return 1
        }
        let canvas: CGFloat = 1024
        let side: CGFloat = 824                     // área do ícone na grade da Apple
        let radius: CGFloat = 185
        let tile = CGRect(x: (canvas - side) / 2, y: (canvas - side) / 2 + 10, width: side, height: side)

        let eye = DragonEye()
        // Renderiza maior que o ícone pra o olho ocupar bem o quadrado.
        let art = CGSize(width: side * 1.15, height: side * 1.15)
        eye.layout(size: art, scale: 1)
        eye.target = CGPoint(x: 0, y: 0)
        eye.settle(seconds: 3)

        guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // sombra
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // olho recortado no quadrado
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.translateBy(x: tile.midX - art.width / 2, y: tile.midY - art.height / 2)
        eye.root.render(in: ctx)
        ctx.restoreGState()

        // borda sutil
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.4, blue: 0.2, alpha: 0.18))
        ctx.setLineWidth(3)
        ctx.strokePath()

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)
        else { return 1 }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? 0 : 1
    }
}
