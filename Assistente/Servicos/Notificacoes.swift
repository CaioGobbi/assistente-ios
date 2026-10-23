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

    static func pedirPermissao() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Refaz a agenda de notificações a partir do banco. Chamadas em sequência viram uma só.
    static func reagendarTudo() {
        agendamento?.cancel()
        agendamento = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let tarefas = (try? Persistencia.container.mainContext.fetch(FetchDescriptor<Tarefa>())) ?? []
            let pedidos = montarPedidos(tarefas, prefs: .atual)
            let centro = UNUserNotificationCenter.current()
            centro.removeAllPendingNotificationRequests()
            for pedido in pedidos {
                guard !Task.isCancelled else { return }
                try? await centro.add(pedido)
            }
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
            pedidos.append(pedido("tarefa-\(t.id.uuidString)", titulo: t.titulo, corpo: corpo, em: t.data!, cal: cal))
        }

        // Resumo da manhã e check-in da noite.
        for deslocamento in 0..<diasAgendados {
            guard let dia = cal.date(byAdding: .day, value: deslocamento, to: inicioHoje),
                  let fim = cal.date(byAdding: .day, value: 1, to: dia) else { continue }
            let doDia = pendentes.filter { t in t.data.map { $0 >= dia && $0 < fim } == true }
            let atrasadas = deslocamento == 0 ? agenda.atrasadas.count : 0

            if let hora = cal.date(byAdding: .minute, value: prefs.minutoBriefing, to: dia), hora > agora {
                pedidos.append(pedido("briefing-\(deslocamento)", titulo: saudacao(prefs.nome),
                                      corpo: textoBriefing(doDia, atrasadas: atrasadas), em: hora, cal: cal))
            }
            if let hora = cal.date(byAdding: .minute, value: prefs.minutoCheckin, to: dia), hora > agora,
               !doDia.isEmpty || atrasadas > 0 {
                pedidos.append(pedido("checkin-\(deslocamento)", titulo: "Fechando o dia",
                                      corpo: textoCheckin(doDia, atrasadas: atrasadas), em: hora, cal: cal))
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
        return "Ainda \(total == 1 ? "falta 1" : "faltam \(total)")\(lista). Fecha agora ou empurra pra amanhã?"
    }

    private static func saudacao(_ nome: String) -> String {
        nome.isEmpty ? "Bom dia!" : "Bom dia, \(nome)!"
    }

    private static func pedido(_ id: String, titulo: String, corpo: String, em data: Date, cal: Calendar) -> UNNotificationRequest {
        let conteudo = UNMutableNotificationContent()
        conteudo.title = titulo
        conteudo.body = corpo
        conteudo.sound = .default
        let quando = cal.dateComponents([.year, .month, .day, .hour, .minute], from: data)
        return UNNotificationRequest(identifier: id, content: conteudo,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: quando, repeats: false))
    }
}
