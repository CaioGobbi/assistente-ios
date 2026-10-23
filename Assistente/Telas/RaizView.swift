import Combine
import SwiftUI
import SwiftData

struct RaizView: View {
    @Environment(Assistente.self) private var assistente
    @State private var nav = Navegacao.shared

    var body: some View {
        TabView(selection: $nav.aba) {
            HojeView(planejar: {
                nav.aba = .assistente
                Task { await assistente.planejarDia() }
            })
            .tabItem { Label("Hoje", systemImage: "sun.max") }
            .tag(Navegacao.Aba.hoje)

            GastosView(
                analisar: { nav.aba = .assistente; nav.pedido = .analisarGastos },
                abrirAjustes: { nav.aba = .ajustes }
            )
            .tabItem { Label("Gastos", systemImage: "creditcard") }
            .tag(Navegacao.Aba.gastos)

            ConversaView(abrirAjustes: { nav.aba = .ajustes })
                .tabItem { Label("Assistente", systemImage: "sparkles") }
                .tag(Navegacao.Aba.assistente)

            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(Navegacao.Aba.ajustes)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Notificacoes.reagendarTudo()
        }
        // Tocou no resumo da manhã, no check-in ou em "Analisar": a conversa já começa no assunto.
        .onChange(of: nav.pedido, initial: true) { _, pedido in
            guard let pedido else { return }
            nav.pedido = nil
            Task {
                switch pedido {
                case .planejar: await assistente.planejarDia()
                case .fecharDia: await assistente.fecharDia()
                case .analisarGastos: await assistente.analisarGastos()
                }
            }
        }
    }
}
