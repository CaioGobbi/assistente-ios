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
                Section { cabecalho(agenda) }

                Section {
                    HStack {
                        TextField("Anotar algo pra hoje…", text: $rapida)
                            .focused($campoRapido)
                            .submitLabel(.next)
                            .onSubmit(adicionarRapida)
                        if !rapida.isEmpty {
                            Button("Adicionar", systemImage: "plus.circle.fill", action: adicionarRapida)
                                .labelStyle(.iconOnly)
                        }
                    }
                }

                if tarefas.isEmpty {
                    ContentUnavailableView(
                        "Nada por aqui ainda",
                        systemImage: "checklist",
                        description: Text("Anote algo acima ou peça pro assistente organizar seu dia.")
                    )
                    .listRowBackground(Color.clear)
                }

                secao("Atrasadas", agenda.atrasadas, destaque: .red)
                secao("Hoje", agenda.hoje)
                secao("Próximos dias", agenda.proximas)
                secao("Sem data", agenda.semData)
                secao("Feitas hoje", agenda.feitasHoje)
            }
            .navigationTitle(saudacao)
            .toolbar {
                Button("Nova tarefa", systemImage: "plus") { criando = true }
            }
            .sheet(item: $editando) { EditarTarefaView(tarefa: $0) }
            .sheet(isPresented: $criando) { EditarTarefaView(tarefa: nil) }
        }
    }

    private var saudacao: String {
        let hora = Calendar.current.component(.hour, from: .now)
        let base = hora < 12 ? "Bom dia" : hora < 18 ? "Boa tarde" : "Boa noite"
        return nome.isEmpty ? base : "\(base), \(nome)"
    }

    @ViewBuilder
    private func cabecalho(_ agenda: Agenda) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let foco = agenda.foco() {
                Text("AGORA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(foco.titulo).font(.title3.weight(.semibold))
                if let rotulo = Formatos.rotulo(foco) {
                    Text(rotulo).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text(agenda.feitasHoje.isEmpty ? "Nada pendente pra hoje." : "Tudo feito por hoje. 🎉")
                    .font(.title3.weight(.semibold))
            }
            Text(resumo(agenda)).font(.footnote).foregroundStyle(.secondary)
            Button(action: planejar) {
                Label("Planejar meu dia", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private func resumo(_ agenda: Agenda) -> String {
        var partes = ["\(agenda.hoje.count) pra hoje", "\(agenda.feitasHoje.count) feitas"]
        if !agenda.atrasadas.isEmpty { partes.append("\(agenda.atrasadas.count) atrasadas") }
        return partes.joined(separator: " · ")
    }

    @ViewBuilder
    private func secao(_ titulo: String, _ lista: [Tarefa], destaque: Color? = nil) -> some View {
        if !lista.isEmpty {
            Section {
                ForEach(lista) { t in
                    LinhaTarefa(tarefa: t, alternar: { alternar(t) })
                        .contentShape(Rectangle())
                        .onTapGesture { editando = t }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Abre para editar")
                        .swipeActions(edge: .leading) {
                            Button(t.concluida ? "Reabrir" : "Feito", systemImage: "checkmark") { alternar(t) }
                                .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Apagar", systemImage: "trash", role: .destructive) { apagar(t) }
                            if !t.concluida {
                                Button("Amanhã", systemImage: "arrow.turn.up.right") { adiar(t) }
                                    .tint(.orange)
                            }
                        }
                }
            } header: {
                Text(titulo).foregroundStyle(destaque ?? .secondary)
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
        HStack(spacing: 12) {
            Button(action: alternar) {
                Image(systemName: tarefa.concluida ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(tarefa.concluida ? .green : .secondary)
                    .symbolEffect(.bounce, value: tarefa.concluida)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(tarefa.titulo)
                    .strikethrough(tarefa.concluida)
                    .foregroundStyle(tarefa.concluida ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let rotulo = Formatos.rotulo(tarefa) { Text(rotulo) }
                    if let m = tarefa.duracaoMinutos { Text("\(m) min") }
                    if tarefa.recorrencia != .nenhuma { Image(systemName: "repeat") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if tarefa.prioridade == .alta && !tarefa.concluida {
                Image(systemName: "flag.fill").foregroundStyle(.orange).accessibilityLabel("Prioridade alta")
            }
        }
        .sensoryFeedback(.success, trigger: tarefa.concluida) { _, feita in feita }
        .accessibilityElement(children: .combine)
        .accessibilityValue(tarefa.concluida ? "Feita" : "")
        .accessibilityAction(named: tarefa.concluida ? "Reabrir" : "Marcar como feita", alternar)
    }
}
