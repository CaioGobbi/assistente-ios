import Combine
import SwiftUI
import SwiftData

struct RaizView: View {
    enum Aba { case hoje, assistente, ajustes }

    @Environment(Assistente.self) private var assistente
    @State private var aba = Aba.hoje

    var body: some View {
        TabView(selection: $aba) {
            HojeView(planejar: {
                aba = .assistente
                Task { await assistente.planejarDia() }
            })
            .tabItem { Label("Hoje", systemImage: "sun.max") }
            .tag(Aba.hoje)

            ConversaView(abrirAjustes: { aba = .ajustes })
                .tabItem { Label("Assistente", systemImage: "sparkles") }
                .tag(Aba.assistente)

            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(Aba.ajustes)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Notificacoes.reagendarTudo()
        }
    }
}
