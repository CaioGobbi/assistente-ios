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
            .tag(Navegacao.Aba.hoje)
            .toolbar(.hidden, for: .tabBar)

            ConversaView(abrirAjustes: { nav.aba = .ajustes })
                .tag(Navegacao.Aba.assistente)
                .toolbar(.hidden, for: .tabBar)

            GastosView(
                analisar: { nav.aba = .assistente; nav.pedido = .analisarGastos },
                abrirAjustes: { nav.aba = .ajustes }
            )
            .tag(Navegacao.Aba.gastos)
            .toolbar(.hidden, for: .tabBar)

            AjustesView()
                .tag(Navegacao.Aba.ajustes)
                .toolbar(.hidden, for: .tabBar)
        }
        .overlay(alignment: .bottom) {
            BarraAbas(aba: $nav.aba)
                .padding(.bottom, 8)
                .ignoresSafeArea(.keyboard)
        }
        .tint(Tema.destaque)
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

/// Barra de abas flutuante, escura e só com ícones.
private struct BarraAbas: View {
    @Binding var aba: Navegacao.Aba

    private struct Item: Identifiable {
        let aba: Navegacao.Aba
        let nome: String
        let icone: String
        var id: String { nome }
    }

    private let itens = [
        Item(aba: .hoje, nome: "Hoje", icone: "sun.max"),
        Item(aba: .assistente, nome: "Assistente", icone: "flame"),
        Item(aba: .gastos, nome: "Gastos", icone: "creditcard"),
        Item(aba: .ajustes, nome: "Ajustes", icone: "slider.horizontal.3"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(itens) { item in
                let ativa = aba == item.aba
                Button {
                    aba = item.aba
                } label: {
                    Image(systemName: item.icone)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(ativa ? Tema.barraIconeAtivo : Tema.barraIcone)
                        .frame(width: 52, height: 44)
                        .background(ativa ? Tema.barraAtiva : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.nome)
                .accessibilityAddTraits(ativa ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Tema.barra, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .sensoryFeedback(.selection, trigger: aba)
        .animation(.snappy(duration: 0.2), value: aba)
    }
}
