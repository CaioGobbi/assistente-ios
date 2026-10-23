import AppIntents
import SwiftData

/// "E aí Siri, anotar no Assistente" — cria uma tarefa para hoje sem abrir o app.
struct AdicionarTarefaIntent: AppIntent {
    static var title: LocalizedStringResource = "Adicionar tarefa"
    static var description = IntentDescription("Anota uma tarefa para hoje no Assistente.")

    @Parameter(title: "Tarefa", requestValueDialog: "O que precisa fazer?")
    var titulo: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistencia.container.mainContext
        context.insert(Tarefa(titulo: titulo, data: Calendar.current.startOfDay(for: .now)))
        try context.save()
        Notificacoes.reagendarTudo()
        return .result(dialog: "Anotado: \(titulo).")
    }
}

struct AtalhosDoAssistente: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AdicionarTarefaIntent(),
            phrases: [
                "Anotar no \(.applicationName)",
                "Adicionar tarefa no \(.applicationName)",
            ],
            shortTitle: "Adicionar tarefa",
            systemImageName: "plus.circle"
        )
    }
}
