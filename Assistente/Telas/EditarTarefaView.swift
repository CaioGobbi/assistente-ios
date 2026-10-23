import SwiftUI
import SwiftData

struct EditarTarefaView: View {
    let tarefa: Tarefa?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var titulo: String
    @State private var notas: String
    @State private var temData: Bool
    @State private var temHorario: Bool
    @State private var data: Date
    @State private var duracao: Int
    @State private var prioridade: Prioridade
    @State private var recorrencia: Recorrencia

    init(tarefa: Tarefa?) {
        self.tarefa = tarefa
        _titulo = State(initialValue: tarefa?.titulo ?? "")
        _notas = State(initialValue: tarefa?.notas ?? "")
        _temData = State(initialValue: tarefa == nil || tarefa?.data != nil)
        _temHorario = State(initialValue: tarefa?.temHorario ?? false)
        _data = State(initialValue: tarefa?.data ?? .now)
        _duracao = State(initialValue: tarefa?.duracaoMinutos ?? 0)
        _prioridade = State(initialValue: tarefa?.prioridade ?? .normal)
        _recorrencia = State(initialValue: tarefa?.recorrencia ?? .nenhuma)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O que precisa fazer?", text: $titulo)
                    TextField("Notas", text: $notas, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    Toggle("Data", isOn: $temData.animation())
                    if temData {
                        Toggle("Horário", isOn: $temHorario.animation())
                        DatePicker("Quando", selection: $data,
                                   displayedComponents: temHorario ? [.date, .hourAndMinute] : [.date])
                        Picker("Repetir", selection: $recorrencia) {
                            ForEach(Recorrencia.allCases) { Text($0.nome).tag($0) }
                        }
                    }
                }

                Section {
                    Picker("Prioridade", selection: $prioridade) {
                        ForEach(Prioridade.allCases) { Text($0.nome).tag($0) }
                    }
                    Stepper(duracao == 0 ? "Duração: não sei" : "Duração: \(duracao) min",
                            value: $duracao, in: 0...480, step: 15)
                }

                if let tarefa {
                    Section {
                        Button("Apagar tarefa", role: .destructive) {
                            context.delete(tarefa)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(tarefa == nil ? "Nova tarefa" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: salvar)
                        .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func salvar() {
        let alvo = tarefa ?? Tarefa(titulo: "")
        alvo.titulo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        alvo.notas = notas
        alvo.temHorario = temData && temHorario
        alvo.data = temData ? (temHorario ? data : Calendar.current.startOfDay(for: data)) : nil
        alvo.recorrencia = temData ? recorrencia : .nenhuma
        alvo.prioridade = prioridade
        alvo.duracaoMinutos = duracao > 0 ? duracao : nil
        if tarefa == nil { context.insert(alvo) }
        try? context.save()
        dismiss()
    }
}
