import SwiftUI

struct ConversaView: View {
    var abrirAjustes: () -> Void

    @Environment(Assistente.self) private var assistente
    @State private var texto = ""
    @State private var confirmandoApagar = false
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
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if assistente.mensagens.isEmpty { vazio }
                        ForEach(assistente.mensagens) { Bolha(mensagem: $0).id($0.id) }
                        if assistente.pensando { pensando.id("pensando") }
                        if let erro = assistente.erro { falha(erro) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
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
            .background(Tema.fundo)
            .safeAreaInset(edge: .top, spacing: 0) { cabecalho }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    barra
                    Color.clear.frame(height: 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Apagar a conversa?", isPresented: $confirmandoApagar, titleVisibility: .visible) {
                Button("Apagar", role: .destructive) { assistente.apagarConversa() }
            } message: {
                Text("A memória e as tarefas continuam.")
            }
        }
    }

    private var cabecalho: some View {
        HStack(spacing: 12) {
            AvatarChama()
            VStack(alignment: .leading, spacing: 1) {
                Text("Tomoshibi")
                    .font(Tema.titulo(22))
                    .foregroundStyle(Tema.tinta)
                Text(assistente.pensando ? "pensando…" : "sempre por aqui")
                    .font(.footnote)
                    .foregroundStyle(Tema.suave)
            }
            Spacer()
            Menu {
                Button("Apagar conversa", systemImage: "trash", role: .destructive) { confirmandoApagar = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Tema.suave)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Mais")
            .disabled(assistente.pensando || assistente.mensagens.isEmpty)
            .padding(.trailing, -10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Tema.fundo)
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No que eu posso ajudar?")
                .font(Tema.titulo(30))
                .foregroundStyle(Tema.tinta)
            Text("Fala o que tem pra fazer, ou pede um plano.")
                .foregroundStyle(Tema.suave)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sugestoes, id: \.self) { s in
                    Button(s) { mandar(s) }
                        .buttonStyle(BotaoPilula(cheio: false))
                }
            }
        }
        .padding(.top, 32)
    }

    private var pensando: some View {
        HStack(spacing: 8) {
            PhaseAnimator([0, 1, 2]) { fase in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Tema.destaque)
                            .frame(width: 6, height: 6)
                            .opacity(i == fase ? 1 : 0.3)
                    }
                }
            } animation: { _ in .easeInOut(duration: 0.35) }
            Text("Pensando…")
                .font(.subheadline)
                .foregroundStyle(Tema.suave)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pensando")
    }

    private func falha(_ erro: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(erro, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Tema.negativo)
            HStack(spacing: 8) {
                if assistente.pendente != nil {
                    Button("Tentar de novo") {
                        Task { await assistente.tentarDeNovo() }
                    }
                    .buttonStyle(BotaoPilula())
                }
                if assistente.faltaChave {
                    Button("Abrir Ajustes", action: abrirAjustes)
                        .buttonStyle(BotaoPilula(cheio: false))
                }
            }
        }
        .cartao(raio: 20, padding: 16)
    }

    private var barra: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("Fala comigo…", text: $texto, axis: .vertical)
                .lineLimit(1...5)
                .focused($digitando)
                .foregroundStyle(Tema.tinta)
                .padding(.vertical, 15)
            Button("Enviar", systemImage: "arrow.up") { mandar(texto) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Tema.fundo)
                .frame(width: 40, height: 40)
                .background(Tema.tinta, in: Circle())
                .frame(width: 44, height: 44)
                .padding(.bottom, 4)
                .buttonStyle(.plain)
                .opacity(podeEnviar ? 1 : 0.3)
                .disabled(!podeEnviar)
        }
        .padding(.leading, 20)
        .padding(.trailing, 4)
        .background(Tema.cartao, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var podeEnviar: Bool {
        !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !assistente.pensando
    }

    private func mandar(_ conteudo: String) {
        texto = ""
        Task { await assistente.enviar(conteudo) }
    }
}

private struct Bolha: View {
    let mensagem: Assistente.Mensagem

    var body: some View {
        Group {
            if mensagem.doUsuario {
                HStack {
                    Spacer(minLength: 48)
                    Text(markdown)
                        .textSelection(.enabled)
                        .foregroundStyle(Tema.tinta)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            Tema.campo,
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                       bottomTrailingRadius: 6, topTrailingRadius: 20,
                                                       style: .continuous)
                        )
                }
            } else {
                // O Tomoshibi fala em texto corrido, sem balão, como numa conversa de mensagens.
                Text(markdown)
                    .textSelection(.enabled)
                    .foregroundStyle(Tema.tinta)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mensagem.doUsuario ? "Você" : "Tomoshibi"): \(mensagem.texto)")
    }

    private var markdown: AttributedString {
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: mensagem.texto, options: opcoes)) ?? AttributedString(mensagem.texto)
    }
}
