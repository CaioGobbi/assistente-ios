import Foundation
import SwiftData

/// Algo que o assistente aprendeu sobre o usuário e leva para toda conversa.
@Model
final class Lembranca {
    var id: UUID
    var texto: String
    var criadaEm: Date

    init(texto: String) {
        self.id = UUID()
        self.texto = texto
        self.criadaEm = .now
    }
}

/// Uma mensagem visível da conversa. O histórico completo da API fica em `Contexto`.
@Model
final class Fala {
    var id: UUID
    var doUsuario: Bool
    var texto: String
    var criadaEm: Date

    init(doUsuario: Bool, texto: String) {
        self.id = UUID()
        self.doUsuario = doUsuario
        self.texto = texto
        self.criadaEm = .now
    }
}
