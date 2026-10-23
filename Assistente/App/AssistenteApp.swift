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
            switch fase {
            case .active:
                Notificacoes.reagendarTudo()
                Task { await Briefing.gerarSePreciso() }
            case .background:
                Briefing.agendar()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Briefing.tarefaID)) {
            await Briefing.gerarSePreciso()
            await Briefing.agendar()
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

    // Toque na notificação abre o app no lugar certo; os botões (Feito, Adiar 1h...) rodam sem abrir.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let tipo = info["tipo"] as? String
        let tarefaID = info["tarefa"] as? String
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await Navegacao.shared.abrir(tipo: tipo)
        } else {
            await Notificacoes.responder(acao: response.actionIdentifier, tarefaID: tarefaID)
        }
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
            return try ModelContainer(for: Tarefa.self, Lembranca.self, Fala.self, Transacao.self)
        } catch {
            fatalError("Não foi possível abrir o banco de dados: \(error)")
        }
    }()
}
