import SwiftUI
import SwiftData

/// O que o assistente sabe sobre você. Dá para corrigir, apagar ou ensinar algo.
struct MemoriaView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Lembranca.criadaEm) private var lembrancas: [Lembranca]
    @State private var nova = ""

    var body: some View {
        List {
            Section {
                TextField("Ensinar algo (ex.: treino às 7h)", text: $nova)
                    .submitLabel(.done)
                    .onSubmit(adicionar)
            } footer: {
                Text("O assistente também guarda coisas sozinho enquanto vocês conversam.")
            }

            if lembrancas.isEmpty {
                ContentUnavailableView("Ainda não sabe nada", systemImage: "brain",
                                       description: Text("Conversa com ele que a memória vai enchendo."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(lembrancas) { l in
                        Text(l.texto)
                    }
                    .onDelete { indices in
                        for i in indices { context.delete(lembrancas[i]) }
                        try? context.save()
                    }
                }
            }
        }
        .fundoTomoshibi()
        .navigationTitle("Memória")
        .toolbar { if !lembrancas.isEmpty { EditButton() } }
    }

    private func adicionar() {
        let texto = nova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        context.insert(Lembranca(texto: texto))
        try? context.save()
        nova = ""
    }
}
