import SwiftUI
import SwiftData

struct HojeView: View {
    var planejar: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var tarefas: [Tarefa]
    @AppStorage(Preferencias.chaveNome) private var nome = ""
    @State private var rapida = ""
    @State private var editando: Tarefa?
    @State private var criando = false
    @FocusState private var campoRapido: Bool

    var body: some View {
        let agenda = Agenda(tarefas)
        NavigationStack {
            List {
                cabecalho(agenda).linhaSolta(topo: 12, base: 20)
                cartaoAgora(agenda).linhaSolta(base: 8)

                if tarefas.isEmpty {
                    ContentUnavailableView(
                        "Nada por aqui ainda",
                        systemImage: "checklist",
                        description: Text("Anote algo abaixo ou peça pro Tomoshibi organizar seu dia.")
                    )
                    .foregroundStyle(Tema.suave)
                    .linhaSolta(topo: 24)
                }

                secao("Atrasadas", agenda.atrasadas, destaque: Tema.negativo)
                secao("Hoje", agenda.hoje)
                secao("Próximos dias", agenda.proximas)
                secao("Sem data", agenda.semData)
                secao("Feitas hoje", agenda.feitasHoje)
            }
            .listStyle(.plain)
            .fundoTomoshibi()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    campoAnotar
                    Color.clear.frame(height: 8)
                }
            }
            .sheet(item: $editando) { EditarTarefaView(tarefa: $0) }
            .sheet(isPresented: $criando) { EditarTarefaView(tarefa: nil) }
        }
    }

    private var saudacao: String {
        let hora = Calendar.current.component(.hour, from: .now)
        let base = hora < 12 ? "Bom dia" : hora < 18 ? "Boa tarde" : "Boa noite"
        return nome.isEmpty ? "\(base)." : "\(base), \(nome)."
    }

    private var dataDeHoje: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR")))
    }

    private func cabecalho(_ agenda: Agenda) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Sobrescrito(texto: dataDeHoje)
                Spacer()
                Button("Nova tarefa", systemImage: "plus") { criando = true }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Tema.tinta)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.trailing, -10)
            }
            .buttonStyle(.plain)
            Text(saudacao)
                .font(Tema.titulo(36))
                .foregroundStyle(Tema.tinta)
            Text(resumo(agenda))
                .font(.body)
                .foregroundStyle(Tema.suave)
        }
    }

    private func cartaoAgora(_ agenda: Agenda) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let foco = agenda.foco() {
                let rotulo = Formatos.rotulo(foco).map { "Agora · \($0)" } ?? "Agora"
                Sobrescrito(texto: rotulo, cor: Tema.destaque)
                VStack(alignment: .leading, spacing: 4) {
                    Text(foco.titulo)
                        .font(Tema.titulo(24))
                        .foregroundStyle(Tema.tinta)
                    if let detalhe = detalhe(foco) {
                        Text(detalhe).font(.subheadline).foregroundStyle(Tema.suave)
                    }
                }
                HStack(spacing: 8) {
                    Button("Feito") { alternar(foco) }
                        .buttonStyle(BotaoPilula())
                    Button("Amanhã") { adiar(foco) }
                        .buttonStyle(BotaoPilula(cheio: false))
                }
            } else {
                Text(agenda.feitasHoje.isEmpty ? "Nada pendente pra hoje." : "Tudo feito por hoje.")
                    .font(Tema.titulo(24))
                    .foregroundStyle(Tema.tinta)
            }
            Button(action: planejar) {
                Label("Planejar meu dia", systemImage: "flame")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Tema.destaque)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .cartao()
    }

    private func detalhe(_ t: Tarefa) -> String? {
        var partes: [String] = []
        if let m = t.duracaoMinutos { partes.append("\(m) min") }
        if !t.notas.isEmpty { partes.append(t.notas) }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    private func resumo(_ agenda: Agenda) -> String {
        var partes = ["\(agenda.hoje.count) pra hoje", "\(agenda.feitasHoje.count) feitas"]
        if !agenda.atrasadas.isEmpty { partes.append("\(agenda.atrasadas.count) atrasadas") }
        return partes.joined(separator: " · ")
    }

    private var campoAnotar: some View {
        HStack(spacing: 4) {
            TextField("Anotar algo pra hoje…", text: $rapida)
                .focused($campoRapido)
                .submitLabel(.next)
                .onSubmit(adicionarRapida)
                .foregroundStyle(Tema.tinta)
            if !rapida.isEmpty {
                Button("Adicionar", systemImage: "arrow.up", action: adicionarRapida)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Tema.fundo)
                    .frame(width: 40, height: 40)
                    .background(Tema.tinta, in: Circle())
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(Tema.cartao, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func secao(_ titulo: String, _ lista: [Tarefa], destaque: Color? = nil) -> some View {
        if !lista.isEmpty {
            TituloSecao(texto: titulo, cor: destaque ?? Tema.suave)
                .linhaSolta(topo: 16, base: 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(lista) { t in
                LinhaTarefa(tarefa: t, alternar: { alternar(t) })
                    .contentShape(Rectangle())
                    .onTapGesture { editando = t }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Abre para editar")
                    .linhaSolta(inicio: 14)
                    .swipeActions(edge: .leading) {
                        Button(t.concluida ? "Reabrir" : "Feito", systemImage: "checkmark") { alternar(t) }
                            .tint(Tema.positivo)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Apagar", systemImage: "trash", role: .destructive) { apagar(t) }
                        if !t.concluida {
                            Button("Amanhã", systemImage: "arrow.turn.up.right") { adiar(t) }
                                .tint(Tema.destaque)
                        }
                    }
            }
        }
    }

    private func adicionarRapida() {
        let titulo = rapida.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titulo.isEmpty else { return }
        context.insert(Tarefa(titulo: titulo, data: Calendar.current.startOfDay(for: .now)))
        rapida = ""
        salvar()
        // Mantém o teclado aberto para anotar várias seguidas.
        campoRapido = true
    }

    private func alternar(_ t: Tarefa) {
        withAnimation {
            if t.concluida { t.reabrir() } else { t.concluir(em: context) }
        }
        salvar()
    }

    private func adiar(_ t: Tarefa) {
        withAnimation { t.adiar() }
        salvar()
    }

    private func apagar(_ t: Tarefa) {
        withAnimation { context.delete(t) }
        salvar()
    }

    private func salvar() {
        try? context.save()
    }
}

struct LinhaTarefa: View {
    let tarefa: Tarefa
    var alternar: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: alternar) {
                ZStack {
                    if tarefa.concluida {
                        Circle().fill(Tema.tinta)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tema.fundo)
                    } else {
                        Circle().strokeBorder(Tema.suave.opacity(0.55), lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)
                .symbolEffect(.bounce, value: tarefa.concluida)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(tarefa.titulo)
                    .font(.body)
                    .strikethrough(tarefa.concluida)
                    .foregroundStyle(tarefa.concluida ? Tema.suave : Tema.tinta)
                HStack(spacing: 6) {
                    if let rotulo = Formatos.rotulo(tarefa) { Text(rotulo) }
                    if let m = tarefa.duracaoMinutos { Text("\(m) min") }
                    if tarefa.recorrencia != .nenhuma { Image(systemName: "repeat") }
                }
                .font(.footnote)
                .foregroundStyle(Tema.suave)
            }

            Spacer()

            if tarefa.prioridade == .alta && !tarefa.concluida {
                Image(systemName: "flag.fill").foregroundStyle(Tema.destaque).accessibilityLabel("Prioridade alta")
            }
        }
        .frame(minHeight: 52)
        .sensoryFeedback(.success, trigger: tarefa.concluida) { _, feita in feita }
        .accessibilityElement(children: .combine)
        .accessibilityValue(tarefa.concluida ? "Feita" : "")
        .accessibilityAction(named: tarefa.concluida ? "Reabrir" : "Marcar como feita", alternar)
    }
}
