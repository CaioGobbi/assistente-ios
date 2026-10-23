import Foundation
import SwiftData

enum Prioridade: Int, CaseIterable, Identifiable {
    case baixa = 0, normal = 1, alta = 2

    var id: Int { rawValue }
    var nome: String {
        switch self {
        case .baixa: "Baixa"
        case .normal: "Normal"
        case .alta: "Alta"
        }
    }
    /// Nome usado nas ferramentas do assistente.
    var chave: String { nome.lowercased() }

    init?(chave: String) {
        guard let p = Self.allCases.first(where: { $0.chave == chave }) else { return nil }
        self = p
    }
}

enum Recorrencia: String, CaseIterable, Identifiable {
    case nenhuma
    case diaria
    case diasUteis = "dias_uteis"
    case semanal

    var id: String { rawValue }
    var nome: String {
        switch self {
        case .nenhuma: "Não repete"
        case .diaria: "Todo dia"
        case .diasUteis: "Dias úteis"
        case .semanal: "Toda semana"
        }
    }

    func proxima(apos data: Date, cal: Calendar = .current) -> Date? {
        switch self {
        case .nenhuma:
            return nil
        case .diaria:
            return cal.date(byAdding: .day, value: 1, to: data)
        case .semanal:
            return cal.date(byAdding: .weekOfYear, value: 1, to: data)
        case .diasUteis:
            var d = data
            repeat {
                guard let seguinte = cal.date(byAdding: .day, value: 1, to: d) else { return nil }
                d = seguinte
            } while cal.isDateInWeekend(d)
            return d
        }
    }
}

@Model
final class Tarefa {
    var id: UUID
    var titulo: String
    var notas: String
    /// Dia da tarefa. Quando `temHorario` é falso, guarda o início do dia.
    var data: Date?
    var temHorario: Bool
    var duracaoMinutos: Int?
    var prioridadeNivel: Int
    var recorrenciaChave: String
    var concluida: Bool
    var concluidaEm: Date?
    var criadaEm: Date

    init(
        titulo: String,
        notas: String = "",
        data: Date? = nil,
        temHorario: Bool = false,
        duracaoMinutos: Int? = nil,
        prioridade: Prioridade = .normal,
        recorrencia: Recorrencia = .nenhuma
    ) {
        self.id = UUID()
        self.titulo = titulo
        self.notas = notas
        self.data = data
        self.temHorario = temHorario
        self.duracaoMinutos = duracaoMinutos
        self.prioridadeNivel = prioridade.rawValue
        self.recorrenciaChave = recorrencia.rawValue
        self.concluida = false
        self.concluidaEm = nil
        self.criadaEm = .now
    }

    var prioridade: Prioridade {
        get { Prioridade(rawValue: prioridadeNivel) ?? .normal }
        set { prioridadeNivel = newValue.rawValue }
    }

    var recorrencia: Recorrencia {
        get { Recorrencia(rawValue: recorrenciaChave) ?? .nenhuma }
        set { recorrenciaChave = newValue.rawValue }
    }

    /// Marca como feita. Se a tarefa repete, cria a próxima ocorrência (nunca no passado).
    @discardableResult
    func concluir(em context: ModelContext, agora: Date = .now, cal: Calendar = .current) -> Tarefa? {
        concluida = true
        concluidaEm = agora
        guard let data, var proxima = recorrencia.proxima(apos: data, cal: cal) else { return nil }
        let inicioHoje = cal.startOfDay(for: agora)
        while proxima < inicioHoje, let seguinte = recorrencia.proxima(apos: proxima, cal: cal) {
            proxima = seguinte
        }
        let nova = Tarefa(
            titulo: titulo, notas: notas, data: proxima, temHorario: temHorario,
            duracaoMinutos: duracaoMinutos, prioridade: prioridade, recorrencia: recorrencia
        )
        context.insert(nova)
        return nova
    }

    func reabrir() {
        concluida = false
        concluidaEm = nil
    }

    /// Empurra a tarefa N dias pra frente, mantendo o horário. Sem data, vai para amanhã.
    func adiar(dias: Int = 1, cal: Calendar = .current) {
        let hoje = cal.startOfDay(for: .now)
        let base = data ?? hoje
        let diaBase = max(cal.startOfDay(for: base), hoje)
        guard let dia = cal.date(byAdding: .day, value: dias, to: diaBase) else { return }
        if temHorario {
            let c = cal.dateComponents([.hour, .minute], from: base)
            data = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: dia)
        } else {
            data = dia
        }
    }

    /// Com horário primeiro, depois por prioridade e por ordem de criação.
    static func ordem(_ a: Tarefa, _ b: Tarefa) -> Bool {
        switch (a.data, b.data) {
        case let (x?, y?):
            if !Calendar.current.isDate(x, inSameDayAs: y) { return x < y }
            if a.temHorario != b.temHorario { return a.temHorario }
            if a.temHorario, x != y { return x < y }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        if a.prioridadeNivel != b.prioridadeNivel { return a.prioridadeNivel > b.prioridadeNivel }
        return a.criadaEm < b.criadaEm
    }
}
