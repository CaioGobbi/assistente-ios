import SwiftUI

struct ConversaView: View {
    var abrirAjustes: () -> Void

    @Environment(Assistente.self) private var assistente
    @State private var texto = ""
    @State private var confirmandoApagar = false

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
                        if assistente.pensando { pensando.id("pensando") }
                        if let erro = assistente.erro { falha(erro) }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistente.mensagens.count) {
                    guard let ultima = assistente.mensagens.last?.id else { return }
                    withAnimation { proxy.scrollTo(ultima, anchor: .bottom) }
                }
                .onChange(of: assistente.pensando) {
                    if assistente.pensando { withAnimation { proxy.scrollTo("pensando", anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { barra }
            .navigationTitle("Assistente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu("Mais", systemImage: "ellipsis.circle") {
                    Button("Apagar conversa", systemImage: "trash", role: .destructive) { confirmandoApagar = true }
                }
                .disabled(assistente.pensando || assistente.mensagens.isEmpty)
            }
            .confirmationDialog("Apagar a conversa?", isPresented: $confirmandoApagar, titleVisibility: .visible) {
                Button("Apagar", role: .destructive) { assistente.apagarConversa() }
            } message: {
                Text("A memória e as tarefas continuam.")
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

    private var pensando: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Pensando…").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func falha(_ erro: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(erro, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
            HStack {
                if assistente.faltaChave {
                    Button("Abrir Ajustes", systemImage: "gearshape", action: abrirAjustes)
                }
                if assistente.pendente != nil {
                    Button("Tentar de novo", systemImage: "arrow.clockwise") {
                        Task { await assistente.tentarDeNovo() }
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var barra: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Mensagem", text: $texto, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            Button("Enviar", systemImage: "arrow.up.circle.fill") { mandar(texto) }
                .labelStyle(.iconOnly)
                .font(.title)
                .frame(minWidth: 44, minHeight: 44)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mensagem.doUsuario ? "Você" : "Assistente"): \(mensagem.texto)")
    }

    private var markdown: AttributedString {
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: mensagem.texto, options: opcoes)) ?? AttributedString(mensagem.texto)
    }
}
