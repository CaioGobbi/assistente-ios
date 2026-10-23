import Foundation
import SwiftData
import UserNotifications

/// Tudo é agendado no próprio iPhone, então funciona com conta Apple grátis (sem push de servidor).
@MainActor
enum Notificacoes {
    private static var agendamento: Task<Void, Never>?
    /// O iOS guarda no máximo 64 notificações pendentes; 14 ficam para resumo e check-in.
    private static let limiteLembretes = 50
    private static let diasAgendados = 7

    enum Acao {
        static let feito = "FEITO"
        static let adiarHora = "ADIAR_1H"
        static let amanha = "AMANHA"
        static let empurrarDia = "EMPURRAR_DIA"
    }

    private enum Categoria {
        static let tarefa = "TAREFA"
        static let checkin = "CHECKIN"
    }

    /// Botões que aparecem ao segurar a notificação. Nenhum abre o app.
    static func registrarCategorias() {
        let feito = UNNotificationAction(identifier: Acao.feito, title: "Feito", options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let hora = UNNotificationAction(identifier: Acao.adiarHora, title: "Adiar 1h", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "clock"))
        let amanha = UNNotificationAction(identifier: Acao.amanha, title: "Amanhã", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "arrow.turn.up.right"))
        let empurrar = UNNotificationAction(identifier: Acao.empurrarDia, title: "Empurrar o resto pra amanhã", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "arrow.turn.up.right"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Categoria.tarefa, actions: [feito, hora, amanha], intentIdentifiers: []),
            UNNotificationCategory(identifier: Categoria.checkin, actions: [empurrar], intentIdentifiers: []),
        ])
    }

    /// Trata o botão tocado na notificação e já refaz a agenda.
    static func responder(acao: String, tarefaID: String?) async {
        let context = Persistencia.container.mainContext
        switch acao {
        case Acao.feito, Acao.adiarHora, Acao.amanha:
            guard let tarefaID, let alvo = UUID(uuidString: tarefaID) else { return }
            var descritor = FetchDescriptor<Tarefa>(predicate: #Predicate { $0.id == alvo })
            descritor.fetchLimit = 1
            guard let t = try? context.fetch(descritor).first, !t.concluida else { return }
            if acao == Acao.feito { t.concluir(em: context) }
            else if acao == Acao.adiarHora { t.data = Date.now.addingTimeInterval(3600); t.temHorario = true }
            else { t.adiar() }
        case Acao.empurrarDia:
            let agenda = Agenda((try? context.fetch(FetchDescriptor<Tarefa>())) ?? [])
            for t in agenda.atrasadas + agenda.hoje { t.adiar() }
        default:
            return
        }
        try? context.save()
        await aplicar()
    }

    static func pedirPermissao() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Refaz a agenda de notificações a partir do banco. Chamadas em sequência viram uma só.
    static func reagendarTudo() {
        agendamento?.cancel()
        agendamento = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await aplicar()
        }
    }

    private static func aplicar() async {
        let tarefas = (try? Persistencia.container.mainContext.fetch(FetchDescriptor<Tarefa>())) ?? []
        let pedidos = montarPedidos(tarefas, prefs: .atual)
        let centro = UNUserNotificationCenter.current()
        centro.removeAllPendingNotificationRequests()
        for pedido in pedidos {
            guard !Task.isCancelled else { return }
            try? await centro.add(pedido)
        }
    }

    static func montarPedidos(_ tarefas: [Tarefa], prefs: Preferencias, agora: Date = .now, cal: Calendar = .current) -> [UNNotificationRequest] {
        let agenda = Agenda(tarefas, agora: agora, cal: cal)
        let pendentes = agenda.pendentes
        let inicioHoje = cal.startOfDay(for: agora)
        let limite = cal.date(byAdding: .day, value: diasAgendados, to: inicioHoje) ?? agora
        var pedidos: [UNNotificationRequest] = []

        // Lembrete na hora de cada tarefa com horário.
        let comHorario = pendentes
            .filter { t in t.temHorario && t.data.map { $0 > agora && $0 < limite } == true }
            .sorted { $0.data! < $1.data! }
            .prefix(limiteLembretes)
        for t in comHorario {
            let corpo = t.notas.isEmpty ? "Tá na hora." : t.notas
            pedidos.append(pedido("tarefa-\(t.id.uuidString)", titulo: t.titulo, corpo: corpo, em: t.data!, cal: cal,
                                  categoria: Categoria.tarefa, grupo: "tarefas", tarefaID: t.id.uuidString))
        }

        // Resumo da manhã e check-in da noite.
        for deslocamento in 0..<diasAgendados {
            guard let dia = cal.date(byAdding: .day, value: deslocamento, to: inicioHoje),
                  let fim = cal.date(byAdding: .day, value: 1, to: dia) else { continue }
            let doDia = pendentes.filter { t in t.data.map { $0 >= dia && $0 < fim } == true }
            let atrasadas = deslocamento == 0 ? agenda.atrasadas.count : 0

            if let hora = cal.date(byAdding: .minute, value: prefs.minutoBriefing, to: dia), hora > agora {
                pedidos.append(pedido("briefing-\(deslocamento)", titulo: saudacao(prefs.nome),
                                      corpo: textoBriefing(doDia, atrasadas: atrasadas), em: hora, cal: cal,
                                      categoria: nil, grupo: "rotina"))
            }
            if let hora = cal.date(byAdding: .minute, value: prefs.minutoCheckin, to: dia), hora > agora,
               !doDia.isEmpty || atrasadas > 0 {
                pedidos.append(pedido("checkin-\(deslocamento)", titulo: "Fechando o dia",
                                      corpo: textoCheckin(doDia, atrasadas: atrasadas), em: hora, cal: cal,
                                      categoria: Categoria.checkin, grupo: "rotina"))
            }
        }
        return pedidos
    }

    static func textoBriefing(_ doDia: [Tarefa], atrasadas: Int) -> String {
        var partes: [String] = []
        if doDia.isEmpty {
            partes.append("Nada marcado pra hoje ainda.")
        } else {
            partes.append("\(doDia.count) \(doDia.count == 1 ? "tarefa" : "tarefas") hoje.")
            if let primeira = doDia.first(where: \.temHorario), let d = primeira.data {
                partes.append("Primeira às \(Formatos.hora.string(from: d)): \(primeira.titulo).")
            } else if let primeira = doDia.first {
                partes.append("Começa por: \(primeira.titulo).")
            }
        }
        if atrasadas > 0 { partes.append("\(atrasadas) atrasada\(atrasadas == 1 ? "" : "s") esperando.") }
        partes.append("Abre pra montar o plano.")
        return partes.joined(separator: " ")
    }

    static func textoCheckin(_ doDia: [Tarefa], atrasadas: Int) -> String {
        let total = doDia.count + atrasadas
        let nomes = doDia.prefix(3).map(\.titulo).joined(separator: ", ")
        let lista = nomes.isEmpty ? "" : ": \(nomes)"
        return "Ainda \(total == 1 ? "falta 1" : "faltam \(total)")\(lista). Segure aqui para empurrar o resto pra amanhã."
    }

    private static func saudacao(_ nome: String) -> String {
        nome.isEmpty ? "Bom dia!" : "Bom dia, \(nome)!"
    }

    private static func pedido(
        _ id: String, titulo: String, corpo: String, em data: Date, cal: Calendar,
        categoria: String?, grupo: String, tarefaID: String? = nil
    ) -> UNNotificationRequest {
        let conteudo = UNMutableNotificationContent()
        conteudo.title = titulo
        conteudo.body = corpo
        conteudo.sound = .default
        conteudo.threadIdentifier = grupo
        if let categoria { conteudo.categoryIdentifier = categoria }
        if let tarefaID { conteudo.userInfo = ["tarefa": tarefaID] }
        let quando = cal.dateComponents([.year, .month, .day, .hour, .minute], from: data)
        return UNNotificationRequest(identifier: id, content: conteudo,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: quando, repeats: false))
    }
}
