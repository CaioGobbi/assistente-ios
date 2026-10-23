import Foundation

/// Chamada direta à Messages API (não há SDK oficial em Swift).
struct ClaudeClient {
    let chave: String
    let modelo: String

    enum Erro: LocalizedError {
        case http(Int, String)
        case recusa

        var errorDescription: String? {
            switch self {
            case .http(401, _): "Chave da API inválida. Confere nos Ajustes."
            case .http(429, _): "Muitas chamadas seguidas. Espera um pouco e tenta de novo."
            case .http(let status, let mensagem): "Erro \(status) da API: \(mensagem)"
            case .recusa: "O Claude não quis responder essa. Tenta reformular."
            }
        }
    }

    func enviar(sistema: String, mensagens: [JSONValue], ferramentas: [JSONValue]) async throws -> JSONValue {
        var corpo: [String: JSONValue] = [
            "model": .string(modelo),
            "max_tokens": 16000,
            "system": .string(sistema),
            "messages": .array(mensagens),
            "tools": .array(ferramentas),
            // Planejar o dia não exige raciocínio longo; mantém rápido e barato.
            "output_config": ["effort": "low"],
            "cache_control": ["type": "ephemeral"],
        ]

        var pedido = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        pedido.httpMethod = "POST"
        pedido.timeoutInterval = 120
        pedido.setValue("application/json", forHTTPHeaderField: "content-type")
        pedido.setValue(chave, forHTTPHeaderField: "x-api-key")
        pedido.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if Self.aceitaFallback(modelo) {
            // Se o modelo recusar por engano, a API tenta de novo em outro modelo.
            corpo["fallbacks"] = "default"
            pedido.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        pedido.httpBody = try JSONEncoder().encode(JSONValue.object(corpo))

        return try await Self.executar(pedido)
    }

    /// Confere se a chave funciona sem gastar tokens (lista um modelo).
    static func testar(chave: String) async throws {
        var pedido = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        pedido.timeoutInterval = 20
        pedido.setValue(chave, forHTTPHeaderField: "x-api-key")
        pedido.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        _ = try await executar(pedido)
    }

    private static func executar(_ pedido: URLRequest) async throws -> JSONValue {
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let json = try? JSONDecoder().decode(JSONValue.self, from: dados)
            throw Erro.http(status, json?["error"]?["message"]?.string ?? String(decoding: dados, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: dados)
    }

    /// Haiku não tem fallback do lado do servidor.
    static func aceitaFallback(_ modelo: String) -> Bool {
        modelo.hasPrefix("claude-opus") || modelo == "claude-sonnet-5-5"
    }
}
