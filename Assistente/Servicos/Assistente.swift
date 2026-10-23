import Foundation
import Observation
import SwiftData

/// A conversa com o Claude. O laço de ferramentas roda aqui: o modelo pede,
/// o app executa no banco local e devolve o resultado.
@MainActor
@Observable
final class Assistente {
    struct Mensagem: Identifiable {
        let id = UUID()
        let doUsuario: Bool
        let texto: String
    }

    private(set) var mensagens: [Mensagem] = []
    private(set) var pensando = false
    var erro: String?

    /// Histórico no formato da API. Só cresce no fim; nunca é editado no meio.
    @ObservationIgnored private var historico: [JSONValue] = []
    @ObservationIgnored private let context: ModelContext

    private static let limiteDeRodadas = 12

    init(context: ModelContext) {
        self.context = context
    }

    func novaConversa() {
        guard !pensando else { return }
        mensagens = []
        historico = []
        erro = nil
    }

    func planejarDia() async {
        await enviar("Monta meu plano de hoje.")
    }

    func enviar(_ entrada: String) async {
        let texto = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !pensando else { return }
        guard let chave = Keychain.ler(Keychain.contaAPI), !chave.isEmpty else {
            erro = "Coloca sua chave da API nos Ajustes primeiro."
            return
        }

        let prefs = Preferencias.atual
        let cliente = ClaudeClient(chave: chave, modelo: prefs.modelo)
        let ferramentas = Ferramentas(context: context)
        let inicio = historico.count

        mensagens.append(Mensagem(doUsuario: true, texto: texto))
        historico.append([
            "role": "user",
            "content": [["type": "text", "text": .string("[\(Formatos.agora())]\n\(texto)")]],
        ])
        pensando = true
        erro = nil
        defer { pensando = false }

        do {
            for _ in 0..<Self.limiteDeRodadas {
                let resposta = try await cliente.enviar(
                    sistema: Self.sistema(prefs), mensagens: historico, ferramentas: Ferramentas.definicoes
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
                    mensagens.append(Mensagem(doUsuario: false, texto: textoResposta))
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
        }
    }

    private static func sistema(_ prefs: Preferencias) -> String {
        let quem = prefs.nome.isEmpty ? "o usuário" : prefs.nome
        return """
        Você é o assistente pessoal de \(quem), dentro de um app de iPhone. Seu trabalho é cuidar da rotina e das tarefas: \
        lembrar, organizar, trazer de volta o que ficou atrasado e ajudar a decidir o que fazer agora.

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
        """
    }
}
