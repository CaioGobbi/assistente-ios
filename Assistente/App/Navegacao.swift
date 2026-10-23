import Foundation
import Observation

/// Aba atual e pedidos que chegam de fora da tela (toque numa notificação).
@MainActor
@Observable
final class Navegacao {
    static let shared = Navegacao()

    enum Aba { case hoje, assistente, ajustes }
    enum Pedido { case planejar, fecharDia }

    var aba = Aba.hoje
    /// Consumido pela RaizView, que repassa ao assistente.
    var pedido: Pedido?

    func abrir(tipo: String?) {
        switch tipo {
        case Notificacoes.Tipo.briefing:
            aba = .assistente
            pedido = .planejar
        case Notificacoes.Tipo.checkin:
            aba = .assistente
            pedido = .fecharDia
        default:
            aba = .hoje
        }
    }
}
