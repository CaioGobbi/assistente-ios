import Foundation

/// Separa as tarefas do jeito que a tela Hoje, as notificações e o assistente enxergam o dia.
struct Agenda {
    private(set) var atrasadas: [Tarefa] = []
    private(set) var hoje: [Tarefa] = []
    private(set) var proximas: [Tarefa] = []
    private(set) var semData: [Tarefa] = []
    private(set) var feitasHoje: [Tarefa] = []

    init(_ tarefas: [Tarefa], agora: Date = .now, cal: Calendar = .current) {
        let inicioHoje = cal.startOfDay(for: agora)
        let inicioAmanha = cal.date(byAdding: .day, value: 1, to: inicioHoje) ?? agora
        for t in tarefas.sorted(by: Tarefa.ordem) {
            if t.concluida {
                if let c = t.concluidaEm, c >= inicioHoje { feitasHoje.append(t) }
                continue
            }
            guard let d = t.data else { semData.append(t); continue }
            if d < inicioHoje { atrasadas.append(t) }
            else if d < inicioAmanha { hoje.append(t) }
            else { proximas.append(t) }
        }
    }

    var pendentes: [Tarefa] { atrasadas + hoje + proximas + semData }

    /// O que fazer agora: a próxima com horário que ainda não passou, senão a atrasada mais antiga, senão a de hoje mais importante.
    func foco(agora: Date = .now) -> Tarefa? {
        let comHorario = hoje.first { t in
            guard t.temHorario, let d = t.data else { return false }
            return d.addingTimeInterval(Double((t.duracaoMinutos ?? 30) * 60)) > agora
        }
        return comHorario ?? atrasadas.first ?? hoje.first { !$0.temHorario }
    }
}
