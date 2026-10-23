import SwiftUI

struct ConversaView: View {
    @Environment(Assistente.self) private var assistente
    @State private var texto = ""
    @FocusState private var digitando: Bool

    private let sugestoes = [
        "Monta meu plano de hoje.",
        "O que tá atrasado?",
        "Organiza minha semana.",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if assistente.mensagens.isEmpty { vazio }
                        ForEach(assistente.mensagens) { Bolha(mensagem: $0).id($0.id) }
                        if assistente.pensando {
                            ProgressView().padding(.leading, 4)
                        }
                        if let erro = assistente.erro {
                            Label(erro, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistente.mensagens.count) {
                    guard let ultima = assistente.mensagens.last?.id else { return }
                    withAnimation { proxy.scrollTo(ultima, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { barra }
            .navigationTitle("Assistente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Nova conversa", systemImage: "square.and.pencil") { assistente.novaConversa() }
                    .disabled(assistente.pensando || assistente.mensagens.isEmpty)
            }
        }
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fala o que tem pra fazer, ou pede um plano.")
                .foregroundStyle(.secondary)
            ForEach(sugestoes, id: \.self) { s in
                Button(s) { mandar(s) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.top, 24)
    }

    private var barra: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Mensagem", text: $texto, axis: .vertical)
                .lineLimit(1...5)
                .focused($digitando)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            Button("Enviar", systemImage: "arrow.up.circle.fill") { mandar(texto) }
                .labelStyle(.iconOnly)
                .font(.title)
                .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistente.pensando)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func mandar(_ conteudo: String) {
        texto = ""
        Task { await assistente.enviar(conteudo) }
    }
}

private struct Bolha: View {
    let mensagem: Assistente.Mensagem

    var body: some View {
        HStack {
            if mensagem.doUsuario { Spacer(minLength: 40) }
            Text(markdown)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    mensagem.doUsuario ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            if !mensagem.doUsuario { Spacer(minLength: 40) }
        }
    }

    private var markdown: AttributedString {
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: mensagem.texto, options: opcoes)) ?? AttributedString(mensagem.texto)
    }
}
