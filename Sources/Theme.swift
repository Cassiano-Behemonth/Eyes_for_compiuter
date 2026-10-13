import AppKit
import ImageIO

/// Cores e imagens do olho. Os temas prontos ficam aqui; os do usuário vêm de
/// ~/Library/Application Support/Eye/Temas/<Nome>/ (tema.json, iris.png, esclera.png, pele.png — tudo opcional).
struct Theme {
    var name: String
    /// Íris, do centro para a borda.
    var iris: [UInt32]
    /// Fibras da íris: clara, média, escura.
    var fibers: [UInt32]
    /// Fundo do olho, do centro para a borda.
    var sclera: [UInt32]
    var veins: UInt32
    /// Escamas e pálpebras na parte mais iluminada; as partes escuras saem desta cor.
    var scales: UInt32
    /// Brilho em volta do olho.
    var glow: UInt32
    /// Pontinhos da senha e o texto embaixo.
    var accent: UInt32

    var irisImage: CGImage?
    var scleraImage: CGImage?
    var skinImage: CGImage?
    /// Muda quando os arquivos de um tema do usuário mudam, pra não reaproveitar o desenho velho do cache.
    var version = ""

    var id: String { name + "|" + version }

    /// Cor das escamas multiplicada por k (k < 1 escurece).
    func scale(_ k: CGFloat, _ alpha: CGFloat = 1) -> CGColor { Self.shade(scales, k, alpha) }

    /// Cor `hex` multiplicada por k.
    static func shade(_ hex: UInt32, _ k: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        func ch(_ shift: UInt32) -> CGFloat { min(1, CGFloat((hex >> shift) & 0xff) / 255 * k) }
        return CGColor(srgbRed: ch(16), green: ch(8), blue: ch(0), alpha: alpha)
    }

    // MARK: - Prontos

    static let dragon = Theme(name: "Dragão",
                              iris: [0xfff1a8, 0xffc23a, 0xff7a0a, 0xe02a00, 0x8a0700, 0x2a0000],
                              fibers: [0xffd25a, 0xff4a00, 0x3a0000],
                              sclera: [0x6e1402, 0x3a0500, 0x120100], veins: 0x2a0000,
                              scales: 0x611a0c, glow: 0xff3a00, accent: 0xff5a2a)

    static let ice = Theme(name: "Gelo",
                           iris: [0xf4ffff, 0xb8f0ff, 0x5ac8ff, 0x1a78e0, 0x0a2f8a, 0x020a2a],
                           fibers: [0xd8f8ff, 0x3aa0ff, 0x001030],
                           sclera: [0x0e3a6e, 0x06203a, 0x010612], veins: 0x000a2a,
                           scales: 0x1a3f61, glow: 0x3aa8ff, accent: 0x6ac8ff)

    static let venom = Theme(name: "Veneno",
                             iris: [0xf6ffb0, 0xc8ff3a, 0x6ee00a, 0x1a9a00, 0x0a4a05, 0x021a00],
                             fibers: [0xe0ff6a, 0x4ac000, 0x0a2a00],
                             sclera: [0x2a5a06, 0x143a02, 0x041200], veins: 0x0a2000,
                             scales: 0x1f4a12, glow: 0x6aff1a, accent: 0x9aff4a)

    static let shadow = Theme(name: "Sombra",
                              iris: [0xffe0ff, 0xe0a0ff, 0xb050ff, 0x7a10e0, 0x3a0680, 0x12002a],
                              fibers: [0xf0c0ff, 0xa040ff, 0x1a0030],
                              sclera: [0x3a0a5e, 0x1e0436, 0x0a0112], veins: 0x140024,
                              scales: 0x3a1a61, glow: 0xb040ff, accent: 0xc070ff)

    static let builtIn = [dragon, ice, venom, shadow]

    /// Tema em uso. Só a main thread troca; quem desenha em segundo plano recebe uma cópia.
    static var current = dragon

    // MARK: - Do usuário

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Eye/Temas", isDirectory: true)
    }

    /// Prontos + os da pasta. Um tema do usuário com o mesmo nome de um pronto substitui o pronto.
    static func all() -> [Theme] {
        let mine = userThemes()
        let names = Set(mine.map(\.name))
        return builtIn.filter { !names.contains($0.name) } + mine
    }

    static func named(_ name: String) -> Theme {
        all().first { $0.name == name } ?? dragon
    }

    private static func userThemes() -> [Theme] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: .skipsHiddenFiles) else { return [] }
        return dirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap(load)
    }

    private struct File: Decodable {
        var base: String?
        var iris: [String]?
        var fibras: [String]?
        var esclera: [String]?
        var veias: String?
        var escamas: String?
        var brilho: String?
        var destaque: String?
    }

    /// Lê uma pasta de tema. Sem tema.json e sem nenhuma imagem, não é tema.
    private static func load(_ dir: URL) -> Theme? {
        let json = dir.appendingPathComponent("tema.json")
        let images = ["iris.png", "esclera.png", "pele.png"].map { dir.appendingPathComponent($0) }
        let files = [json] + images
        let fm = FileManager.default
        guard files.contains(where: { fm.fileExists(atPath: $0.path) }) else { return nil }

        var file = File()
        if let data = try? Data(contentsOf: json) {
            do {
                file = try JSONDecoder().decode(File.self, from: data)
            } catch {
                NSLog("Eye: tema.json inválido em %@: %@", dir.path, String(describing: error))
            }
        }

        let base = file.base.flatMap { b in builtIn.first { $0.name == b } } ?? dragon
        var t = base
        t.name = dir.lastPathComponent
        t.iris = colors(file.iris, min: 2) ?? base.iris
        t.fibers = colors(file.fibras, min: 3).map { Array($0.prefix(3)) } ?? base.fibers
        t.sclera = colors(file.esclera, min: 2) ?? base.sclera
        t.veins = file.veias.flatMap(hex) ?? base.veins
        t.scales = file.escamas.flatMap(hex) ?? base.scales
        t.glow = file.brilho.flatMap(hex) ?? base.glow
        t.accent = file.destaque.flatMap(hex) ?? base.accent
        t.irisImage = image(images[0])
        t.scleraImage = image(images[1])
        t.skinImage = image(images[2])
        t.version = files.compactMap { url -> String? in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { String($0.timeIntervalSince1970) }
        }.joined(separator: ",")
        return t
    }

    private static func colors(_ list: [String]?, min count: Int) -> [UInt32]? {
        guard let list else { return nil }
        let parsed = list.compactMap(hex)
        return parsed.count == list.count && parsed.count >= count ? parsed : nil
    }

    /// "#ff6a00" ou "ff6a00".
    private static func hex(_ s: String) -> UInt32? {
        let h = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        return UInt32(h, radix: 16)
    }

    private static func image(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
