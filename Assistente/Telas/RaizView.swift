import Combine
import SwiftUI
import SwiftData

struct RaizView: View {
    @Environment(Assistente.self) private var assistente
    @State private var nav = Navegacao.shared
    @AppStorage(Aparencia.chave) private var aparencia = Aparencia.claro

    var body: some View {
        TabView(selection: $nav.aba) {
            HojeView(planejar: {
                nav.aba = .assistente
                Task { await assistente.planejarDia() }
            })
            .tabItem { Label("Hoje", systemImage: "sun.max") }
            .tag(Navegacao.Aba.hoje)

            ConversaView(abrirAjustes: { nav.aba = .ajustes })
                .tabItem { Label("Assistente", systemImage: "flame") }
                .tag(Navegacao.Aba.assistente)

            GastosView(
                analisar: { nav.aba = .assistente; nav.pedido = .analisarGastos },
                abrirAjustes: { nav.aba = .ajustes }
            )
            .tabItem { Label("Gastos", systemImage: "creditcard") }
            .tag(Navegacao.Aba.gastos)

            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
                .tag(Navegacao.Aba.ajustes)
        }
        .tint(Tema.tinta)
        .sensoryFeedback(.selection, trigger: nav.aba)
        .preferredColorScheme(aparencia.esquema)
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

