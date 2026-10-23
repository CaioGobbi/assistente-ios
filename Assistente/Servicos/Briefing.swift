import BackgroundTasks
import Foundation
import SwiftData

/// Resumo da manhã escrito pelo Claude. O iOS acorda o app um pouco antes do horário
/// (quando quiser; não é garantido) e o texto vira o corpo da notificação.
/// Se as tarefas do dia mudarem depois, volta o resumo simples montado no próprio app.
@MainActor
enum Briefing {
    static let tarefaID = "com.caiogobbi.assistente.briefing"
    private static let chaveUltimaGeracao = "briefing-ultima-geracao"
    private static let intervaloMinimo: TimeInterval = 30 * 60

    private struct Salvo: Codable {
        var texto: String
        var assinatura: String
    }

    /// Identifica as tarefas de um dia; muda se alguma for criada, movida ou renomeada.
    static func assinatura(_ doDia: [Tarefa]) -> String {
        doDia.map { "\($0.id.uuidString)|\($0.titulo)|\($0.data?.timeIntervalSince1970 ?? 0)" }
            .sorted().joined(separator: ";")
    }

    static func texto(para dia: Date, doDia: [Tarefa]) -> String? {
        guard let dados = UserDefaults.standard.data(forKey: chaveDoDia(dia)),
              let salvo = try? JSONDecoder().decode(Salvo.self, from: dados),
              salvo.assinatura == assinatura(doDia) else { return nil }
        return salvo.texto
    }

    /// Pede ao iOS para acordar o app umas horas antes do próximo resumo.
    static func agendar(agora: Date = .now, cal: Calendar = .current) {
        let hoje = cal.startOfDay(for: agora)
        guard var alvo = cal.date(byAdding: .minute, value: Preferencias.atual.minutoBriefing - 120, to: hoje) else { return }
        if alvo <= agora { alvo = cal.date(byAdding: .day, value: 1, to: alvo) ?? alvo }
        let pedido = BGAppRefreshTaskRequest(identifier: tarefaID)
        pedido.earliestBeginDate = alvo
        try? BGTaskScheduler.shared.submit(pedido)
    }

    /// Gera (se faltar ou estiver velho) o texto do próximo resumo e refaz as notificações.
    static func gerarSePreciso(agora: Date = .now, cal: Calendar = .current) async {
        let defaults = UserDefaults.standard
        if let ultima = defaults.object(forKey: chaveUltimaGeracao) as? Date, agora.timeIntervalSince(ultima) < intervaloMinimo {
            return
        }
        guard let chave = Keychain.ler(Keychain.contaAPI), !chave.isEmpty else { return }

        let prefs = Preferencias.atual
        let hoje = cal.startOfDay(for: agora)
        let horaDeHoje = cal.date(byAdding: .minute, value: prefs.minutoBriefing, to: hoje) ?? agora
        // Depois do resumo de hoje, prepara o de amanhã.
        guard let dia = agora < horaDeHoje ? hoje : cal.date(byAdding: .day, value: 1, to: hoje) else { return }

        let context = Persistencia.container.mainContext
        let agenda = Agenda((try? context.fetch(FetchDescriptor<Tarefa>())) ?? [], agora: dia, cal: cal)
        let doDia = agenda.hoje
        guard texto(para: dia, doDia: doDia) == nil else { return }
        defaults.set(agora, forKey: chaveUltimaGeracao)

        let lembrancas = (try? context.fetch(FetchDescriptor<Lembranca>())) ?? []
        let pedido = """
        Escreva o corpo da notificação do resumo da manhã de \(Formatos.dia.string(from: dia)).
        Até 170 caracteres, português do Brasil, casual e direto, sem saudação (o título já cumprimenta).
        Diga o foco do dia e o primeiro compromisso com horário, se houver. Responda só com o texto.

        Tarefas do dia:
        \(doDia.isEmpty ? "(nenhuma)" : doDia.map(linha).joined(separator: "\n"))

        Atrasadas: \(agenda.atrasadas.isEmpty ? "nenhuma" : agenda.atrasadas.map(\.titulo).joined(separator: ", "))

        O que você sabe da pessoa:
        \(lembrancas.isEmpty ? "(nada)" : lembrancas.map { "- \($0.texto)" }.joined(separator: "\n"))
        """

        let cliente = ClaudeClient(chave: chave, modelo: prefs.modelo)
        guard let resposta = try? await cliente.enviar(
            sistema: "Você escreve notificações curtas de um assistente pessoal de rotina.",
            mensagens: [["role": "user", "content": .string(pedido)]],
            ferramentas: []
        ), resposta["stop_reason"]?.string != "refusal" else { return }

        let texto = (resposta["content"]?.array ?? [])
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty,
              let dados = try? JSONEncoder().encode(Salvo(texto: texto, assinatura: assinatura(doDia))) else { return }
        defaults.set(dados, forKey: chaveDoDia(dia))
        await Notificacoes.aplicar()
    }

    private static func chaveDoDia(_ dia: Date) -> String {
        "briefing-\(Formatos.dia.string(from: dia))"
    }

    private static func linha(_ t: Tarefa) -> String {
        var partes = ["-"]
        if t.temHorario, let d = t.data { partes.append(Formatos.hora.string(from: d)) }
        partes.append(t.titulo)
        if t.prioridade == .alta { partes.append("(prioridade alta)") }
        return partes.joined(separator: " ")
    }
}
