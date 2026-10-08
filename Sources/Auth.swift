import CommonCrypto
import Foundation
import OpenDirectory

/// Confere a senha do usuário logado no macOS (a mesma do login) ou a senha secreta do Eye.
enum Auth {
    // Senha secreta: só o PBKDF2-SHA256 dela fica aqui, nunca o texto.
    private static let secretSalt = "6d8ee9046b51067ef764d231e1b64824"
    private static let secretHash = "c950b63b79869dda7ece2a5cb6d495ae28590f825a827031a5bff468b3c22757"
    private static let secretRounds: UInt32 = 200_000

    private static func userRecord() throws -> ODRecord {
        let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
        return try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
    }

    /// O registro do usuário foi encontrado? Se não, não dá pra desbloquear com senha.
    static let isAvailable: Bool = (try? userRecord()) != nil

    /// Lento (PBKDF2), chame fora da main thread.
    static func verify(_ password: String) -> Bool {
        if isSecret(password) { return true }
        guard let record = try? userRecord() else { return false }
        do {
            try record.verifyPassword(password)
            return true
        } catch {
            return false
        }
    }

    private static func isSecret(_ password: String) -> Bool {
        let pw = Array(password.utf8).map { Int8(bitPattern: $0) }
        let salt = bytes(fromHex: secretSalt)
        var out = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.count, salt, salt.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), secretRounds, &out, out.count)
        guard status == kCCSuccess else { return false }
        // Comparação em tempo constante.
        return zip(out, bytes(fromHex: secretHash)).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func bytes(fromHex hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            result.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return result
    }
}
