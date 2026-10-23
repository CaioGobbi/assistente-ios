import SwiftUI
import SwiftData

struct EditarTarefaView: View {
    let tarefa: Tarefa?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private struct Rascunho: Equatable {
        var titulo = ""
        var notas = ""
        var temData = true
        var temHorario = false
        var data = Date.now
        var duracao = 0
        var prioridade = Prioridade.normal
        var recorrencia = Recorrencia.nenhuma
    }

    private let original: Rascunho
    @State private var r: Rascunho
    @State private var confirmandoApagar = false
    @FocusState private var tituloFocado: Bool

    init(tarefa: Tarefa?) {
        self.tarefa = tarefa
        var base = Rascunho()
        if let t = tarefa {
            base = Rascunho(
                titulo: t.titulo, notas: t.notas, temData: t.data != nil, temHorario: t.temHorario,
                data: t.data ?? .now, duracao: t.duracaoMinutos ?? 0,
                prioridade: t.prioridade, recorrencia: t.recorrencia
            )
        }
        original = base
        _r = State(initialValue: base)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O que precisa fazer?", text: $r.titulo)
                        .focused($tituloFocado)
                    TextField("Notas", text: $r.notas, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    Toggle("Data", isOn: $r.temData.animation())
                    if r.temData {
                        Toggle("Horário", isOn: $r.temHorario.animation())
                        DatePicker("Quando", selection: $r.data,
                                   displayedComponents: r.temHorario ? [.date, .hourAndMinute] : [.date])
                        Picker("Repetir", selection: $r.recorrencia) {
                            ForEach(Recorrencia.allCases) { Text($0.nome).tag($0) }
                        }
                    }
                }

                Section {
                    Picker("Prioridade", selection: $r.prioridade) {
                        ForEach(Prioridade.allCases) { Text($0.nome).tag($0) }
                    }
                    Stepper(r.duracao == 0 ? "Duração: não sei" : "Duração: \(r.duracao) min",
                            value: $r.duracao, in: 0...480, step: 15)
                }

                if tarefa != nil {
                    Section {
                        Button("Apagar tarefa", role: .destructive) { confirmandoApagar = true }
                    }
                }
            }
            .navigationTitle(tarefa == nil ? "Nova tarefa" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: salvar)
                        .disabled(r.titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Apagar esta tarefa?", isPresented: $confirmandoApagar, titleVisibility: .visible) {
                Button("Apagar", role: .destructive, action: apagar)
            }
            // Evita perder alterações num swipe sem querer.
            .interactiveDismissDisabled(r != original)
            .task { if tarefa == nil { tituloFocado = true } }
        }
    }

    private func salvar() {
        let alvo = tarefa ?? Tarefa(titulo: "")
        alvo.titulo = r.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        alvo.notas = r.notas
        alvo.temHorario = r.temData && r.temHorario
        alvo.data = r.temData ? (r.temHorario ? r.data : Calendar.current.startOfDay(for: r.data)) : nil
        alvo.recorrencia = r.temData ? r.recorrencia : .nenhuma
        alvo.prioridade = r.prioridade
        alvo.duracaoMinutos = r.duracao > 0 ? r.duracao : nil
        if tarefa == nil { context.insert(alvo) }
        try? context.save()
        dismiss()
    }

    private func apagar() {
        guard let tarefa else { return }
        context.delete(tarefa)
        try? context.save()
        dismiss()
    }
}
