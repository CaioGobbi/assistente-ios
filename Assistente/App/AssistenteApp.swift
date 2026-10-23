import SwiftUI
import SwiftData
import UserNotifications

@main
struct AssistenteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var assistente = Assistente(context: Persistencia.container.mainContext)

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(assistente)
                .task { await Notificacoes.pedirPermissao() }
        }
        .modelContainer(Persistencia.container)
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { Notificacoes.reagendarTudo() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notificacoes.registrarCategorias()
        return true
    }

    // Botões da notificação (Feito, Adiar 1h, Amanhã...). Roda sem abrir o app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let tarefaID = response.notification.request.content.userInfo["tarefa"] as? String
        await Notificacoes.responder(acao: response.actionIdentifier, tarefaID: tarefaID)
    }

    // Mostra o lembrete mesmo com o app aberto.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum Persistencia {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Tarefa.self)
        } catch {
            fatalError("Não foi possível abrir o banco de dados: \(error)")
        }
    }()
}
