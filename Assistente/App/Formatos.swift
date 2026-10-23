import Foundation

enum Formatos {
    /// "2026-10-23", usado na conversa com o Claude.
    static let dia: DateFormatter = fixo("yyyy-MM-dd")
    /// "09:30"
    static let hora: DateFormatter = fixo("HH:mm")

    private static func fixo(_ formato: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = formato
        return f
    }

    /// Carimbo de data e hora que vai no início de cada mensagem para o Claude.
    static func agora(_ data: Date = .now) -> String {
        let longo = data.formatted(
            .dateTime.weekday(.wide).day().month(.wide).year().hour().minute()
                .locale(Locale(identifier: "pt_BR"))
        )
        return "agora: \(longo) (\(dia.string(from: data)) \(hora.string(from: data)))"
    }

    /// Junta "AAAA-MM-DD" e "HH:mm" numa data. Hora sem dia vale para hoje.
    static func combinar(dia textoDia: String?, hora textoHora: String?, cal: Calendar = .current) throws -> (data: Date?, temHorario: Bool) {
        if textoDia == nil && textoHora == nil { return (nil, false) }
        var base = cal.startOfDay(for: .now)
        if let textoDia {
            guard let d = dia.date(from: textoDia) else { throw FalhaFerramenta("Data inválida '\(textoDia)'. Use AAAA-MM-DD.") }
            base = cal.startOfDay(for: d)
        }
        guard let textoHora else { return (base, false) }
        guard let h = hora.date(from: textoHora) else { throw FalhaFerramenta("Hora inválida '\(textoHora)'. Use HH:mm.") }
        let c = cal.dateComponents([.hour, .minute], from: h)
        let data = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: base)
        return (data, true)
    }

    /// "R$ 1.234,56"
    static func reais(_ valor: Double) -> String {
        valor.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }

    /// "Hoje", "Ontem", "qua., 22 de out."
    static func rotulo(dia data: Date, cal: Calendar = .current) -> String {
        if cal.isDateInToday(data) { return "Hoje" }
        if cal.isDateInYesterday(data) { return "Ontem" }
        return data.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
    }

    /// "Hoje 09:30", "Amanhã", "sex., 24 de out."
    static func rotulo(_ t: Tarefa, cal: Calendar = .current) -> String? {
        guard let data = t.data else { return nil }
        let diaTexto: String
        if cal.isDateInToday(data) { diaTexto = "Hoje" }
        else if cal.isDateInTomorrow(data) { diaTexto = "Amanhã" }
        else if cal.isDateInYesterday(data) { diaTexto = "Ontem" }
        else { diaTexto = data.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "pt_BR"))) }
        return t.temHorario ? "\(diaTexto) \(hora.string(from: data))" : diaTexto
    }
}

struct FalhaFerramenta: LocalizedError {
    let errorDescription: String?
    init(_ mensagem: String) { errorDescription = mensagem }
}
