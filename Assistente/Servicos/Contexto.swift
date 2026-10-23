import Foundation

/// Histórico da conversa no formato da API, salvo em arquivo.
/// Recomeça a cada dia: o que importa de um dia pro outro vai para a memória,
/// e assim o histórico nunca precisa ser cortado ou editado no meio.
enum Contexto {
    private struct Salvo: Codable {
        var dia: Date
        var historico: [JSONValue]
    }

    private static var arquivo: URL {
        URL.applicationSupportDirectory.appending(path: "contexto.json")
    }

    static func carregar(cal: Calendar = .current) -> [JSONValue] {
        guard let dados = try? Data(contentsOf: arquivo),
              let salvo = try? JSONDecoder().decode(Salvo.self, from: dados),
              cal.isDateInToday(salvo.dia) else { return [] }
        return salvo.historico
    }

    static func salvar(_ historico: [JSONValue]) {
        let salvo = Salvo(dia: .now, historico: historico)
        guard let dados = try? JSONEncoder().encode(salvo) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? dados.write(to: arquivo, options: .atomic)
    }
}
