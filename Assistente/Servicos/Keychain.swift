import Foundation
import Security

enum Keychain {
    static let contaAPI = "anthropic-api-key"
    static let contaPluggyID = "pluggy-client-id"
    static let contaPluggySecret = "pluggy-client-secret"
    static let contaPluggyItens = "pluggy-item-ids"
    private static let servico = "com.caiogobbi.assistente"

    static func ler(_ conta: String) -> String? {
        var consulta = base(conta)
        consulta[kSecReturnData as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let dados = resultado as? Data else { return nil }
        return String(data: dados, encoding: .utf8)
    }

    /// Valor vazio apaga o item.
    static func salvar(_ valor: String, conta: String) {
        SecItemDelete(base(conta) as CFDictionary)
        guard !valor.isEmpty else { return }
        var novo = base(conta)
        novo[kSecValueData as String] = Data(valor.utf8)
        novo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(novo as CFDictionary, nil)
    }

    private static func base(_ conta: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
        ]
    }
}
