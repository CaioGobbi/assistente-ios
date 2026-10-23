import Foundation

/// Ajustes simples guardados no UserDefaults. As telas usam as mesmas chaves via @AppStorage.
struct Preferencias {
    static let chaveNome = "nome"
    static let chaveModelo = "modelo"
    static let chaveBriefing = "minutoBriefing"
    static let chaveCheckin = "minutoCheckin"

    static let modeloPadrao = "claude-opus-5-5"
    static let briefingPadrao = 7 * 60 + 30
    static let checkinPadrao = 21 * 60

    struct Modelo: Identifiable {
        let id: String
        let nome: String
    }

    static let modelos = [
        Modelo(id: "claude-opus-5-5", nome: "Opus 5.5 (mais esperto)"),
        Modelo(id: "claude-sonnet-5-5", nome: "Sonnet 5.5 (equilibrado)"),
        Modelo(id: "claude-haiku-5-5", nome: "Haiku 5.5 (mais barato)"),
    ]

    var nome: String
    var modelo: String
    /// Minutos desde a meia-noite.
    var minutoBriefing: Int
    var minutoCheckin: Int

    static var atual: Preferencias {
        let d = UserDefaults.standard
        return Preferencias(
            nome: d.string(forKey: chaveNome) ?? "",
            modelo: d.string(forKey: chaveModelo) ?? modeloPadrao,
            minutoBriefing: d.object(forKey: chaveBriefing) as? Int ?? briefingPadrao,
            minutoCheckin: d.object(forKey: chaveCheckin) as? Int ?? checkinPadrao
        )
    }
}
