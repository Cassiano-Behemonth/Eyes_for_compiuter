import Foundation

final class Settings {
    private let defaults = UserDefaults.standard

    /// Vigiando (bloqueia automaticamente quando você sai).
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// Segundos sem ninguém na câmera até bloquear.
    var absenceDelay: TimeInterval {
        get { defaults.object(forKey: "absenceDelay") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "absenceDelay") }
    }

    /// uniqueID da câmera escolhida (nil = a câmera embutida).
    var cameraID: String? {
        get { defaults.string(forKey: "cameraID") }
        set { defaults.set(newValue, forKey: "cameraID") }
    }

    /// Espelha a imagem da câmera (pra o olho olhar pro lado certo).
    var mirror: Bool {
        get { defaults.object(forKey: "mirror") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "mirror") }
    }

    /// Nome do tema do olho (pronto ou da pasta de temas).
    var theme: String {
        get { defaults.string(forKey: "theme") ?? Theme.dragon.name }
        set { defaults.set(newValue, forKey: "theme") }
    }

    /// Modo teste: Forçar Encerrar (⌥⌘⎋) continua funcionando enquanto bloqueado.
    var safeMode: Bool {
        get { defaults.object(forKey: "safeMode") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "safeMode") }
    }
}
