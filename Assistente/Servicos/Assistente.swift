import Foundation
import Observation
import SwiftData

/// A conversa com o Claude. O laço de ferramentas roda aqui: o modelo pede,
/// o app executa no banco local e devolve o resultado.
@MainActor
@Observable
final class Assistente {
    struct Mensagem: Identifiable {
        let id: UUID
        let doUsuario: Bool
        let texto: String
    }

    private(set) var mensagens: [Mensagem] = []
    private(set) var pensando = false
    private(set) var erro: String?
    /// A chave da API não está configurada; a tela oferece um atalho para Ajustes.
    private(set) var faltaChave = false
    /// Texto da última mensagem que falhou, para "Tentar de novo".
    private(set) var pendente: String?

    /// Histórico no formato da API. Só cresce no fim; nunca é editado no meio.
    @ObservationIgnored private var historico: [JSONValue]
    @ObservationIgnored private var diaDoHistorico = Date.now
    @ObservationIgnored private let context: ModelContext

    private static let limiteDeRodadas = 12
    private static let falasCarregadas = 200

    init(context: ModelContext) {
        self.context = context
        self.historico = Contexto.carregar()
        var descritor = FetchDescriptor<Fala>(sortBy: [SortDescriptor(\.criadaEm, order: .reverse)])
        descritor.fetchLimit = Self.falasCarregadas
        let falas = (try? context.fetch(descritor)) ?? []
        self.mensagens = falas.reversed().map { Mensagem(id: $0.id, doUsuario: $0.doUsuario, texto: $0.texto) }
    }

    func apagarConversa() {
        guard !pensando else { return }
        try? context.delete(model: Fala.self)
        try? context.save()
        mensagens = []
        historico = []
        Contexto.salvar(historico)
        erro = nil
        faltaChave = false
        pendente = nil
    }

    func planejarDia() async {
        await enviar("Monta meu plano de hoje.")
    }

    func fecharDia() async {
        await enviar("Bora fechar o dia. O que ficou pendente e o que eu faço com isso?")
    }

    func analisarGastos() async {
        await enviar("Analisa meus gastos dos últimos 30 dias: pra onde tá indo o dinheiro e onde dá pra cortar.")
    }

    func enviar(_ entrada: String) async {
        let texto = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !pensando else { return }
        registrar(doUsuario: true, texto: texto)
        await rodar(texto)
    }

    func tentarDeNovo() async {
        guard let texto = pendente, !pensando else { return }
        await rodar(texto)
    }

    private func rodar(_ texto: String) async {
        erro = nil
        faltaChave = false
        pendente = nil
        guard let chave = Keychain.ler(Keychain.contaAPI), !chave.isEmpty else {
            erro = "Falta a chave da API do Claude."
            faltaChave = true
            pendente = texto
            return
        }

        // Virou o dia com o app aberto: começa um contexto novo.
        if !Calendar.current.isDateInToday(diaDoHistorico) {
            historico = []
            diaDoHistorico = .now
        }

        let prefs = Preferencias.atual
        let cliente = ClaudeClient(chave: chave, modelo: prefs.modelo)
        let ferramentas = Ferramentas(context: context)
        let inicio = historico.count

        historico.append([
            "role": "user",
            "content": [["type": "text", "text": .string("[\(Formatos.agora())]\n\(texto)")]],
        ])
        pensando = true
        defer {
            pensando = false
            Contexto.salvar(historico)
        }

        do {
            for _ in 0..<Self.limiteDeRodadas {
                let resposta = try await cliente.enviar(
                    sistema: sistema(prefs), mensagens: historico, ferramentas: Ferramentas.definicoes
                )
                let parada = resposta["stop_reason"]?.string
                if parada == "refusal" { throw ClaudeClient.Erro.recusa }

                let conteudo = resposta["content"]?.array ?? []
                historico.append(["role": "assistant", "content": .array(conteudo)])

                let textoResposta = conteudo
                    .filter { $0["type"]?.string == "text" }
                    .compactMap { $0["text"]?.string }
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !textoResposta.isEmpty {
                    registrar(doUsuario: false, texto: textoResposta)
                }

                let usos = conteudo.filter { $0["type"]?.string == "tool_use" }
                guard parada == "tool_use", !usos.isEmpty else { return }

                // Todos os resultados voltam numa única mensagem.
                let resultados: [JSONValue] = usos.map { uso -> JSONValue in
                    let r = ferramentas.executar(nome: uso["name"]?.string ?? "", entrada: uso["input"] ?? .object([:]))
                    return [
                        "type": "tool_result",
                        "tool_use_id": uso["id"] ?? .null,
                        "content": .string(r.texto),
                        "is_error": .bool(r.erro),
                    ]
                }
                historico.append(["role": "user", "content": .array(resultados)])
            }
            throw FalhaFerramenta("O assistente se enrolou nessa. Tenta de novo com outras palavras.")
        } catch {
            // Descarta a rodada incompleta para a próxima mensagem começar de um histórico válido.
            historico.removeSubrange(inicio...)
            erro = error.localizedDescription
            pendente = texto
        }
    }

    private func registrar(doUsuario: Bool, texto: String) {
        let fala = Fala(doUsuario: doUsuario, texto: texto)
        context.insert(fala)
        try? context.save()
        mensagens.append(Mensagem(id: fala.id, doUsuario: doUsuario, texto: texto))
    }

    private func sistema(_ prefs: Preferencias) -> String {
        let quem = prefs.nome.isEmpty ? "o usuário" : prefs.nome
        let lembrancas = (try? context.fetch(FetchDescriptor<Lembranca>(sortBy: [SortDescriptor(\.criadaEm)]))) ?? []
        let memoria = lembrancas.isEmpty
            ? "(nada ainda)"
            : lembrancas.map { "- [\($0.id.uuidString)] \($0.texto)" }.joined(separator: "\n")
        return """
        Você é o assistente pessoal de \(quem), dentro de um app de iPhone. Seu trabalho é cuidar da rotina e das tarefas: \
        lembrar, organizar, trazer de volta o que ficou atrasado e ajudar a decidir o que fazer agora. Você acompanha a \
        pessoa no dia a dia, então aja como alguém que já a conhece.

        Jeito de falar: português do Brasil, casual e direto, como um parceiro. Respostas curtas, que caibam na tela do \
        celular. Pode usar negrito e listas simples; nada de títulos.

        Como trabalhar:
        - Cada mensagem começa com a data e a hora atuais entre colchetes. Use isso para entender "hoje", "amanhã" e "mais tarde".
        - Antes de falar da agenda, chame listar_tarefas. Nunca invente tarefas.
        - Quando o usuário citar algo para fazer, crie a tarefa direto, sem pedir confirmação. Se não houver horário, deixe sem.
        - Ao planejar o dia: comece pelo que tem horário, encaixe as prioridades altas nos intervalos, estime a duração do \
        que não tem e diga se o dia não fecha. Proponha mover o que não cabe e, se o usuário topar, reagende.
        - Tarefas atrasadas: traga à tona sem sermão e sugira uma data nova.
        - Depois de mexer nas tarefas, confirme em uma linha o que mudou.

        Dinheiro: o app tem as transações do banco do usuário. Antes de falar de gastos, chame consultar_gastos; nunca \
        invente valores. Valores em reais. Aponte padrões (onde mais gasta, gastos pequenos que somam muito, assinaturas, \
        delivery) e sugira cortes concretos, sem sermão. Se não houver transações, diga para conectar o banco ou importar \
        um extrato na aba Gastos.

        Memória: a conversa recomeça todo dia, então guarde com a ferramenta lembrar o que vale para os próximos dias: \
        rotina (horário de acordar, treino, trabalho), preferências, metas, pessoas e compromissos recorrentes. Guarde sem \
        avisar, um fato curto por vez, e não guarde o que já é tarefa. Se algo mudar ou ficar velho, use esquecer. \
        Use o que sabe para personalizar o plano sem ficar repetindo que lembrou.

        O que você já sabe sobre \(quem):
        \(memoria)
        """
    }
}
