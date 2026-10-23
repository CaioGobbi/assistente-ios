import Foundation
import SwiftData

/// Puxa as transações dos bancos conectados no Meu Pluggy (Open Finance, só leitura).
@MainActor
enum Banco {
    nonisolated static let prefixo = "banco-"
    /// Momento da última sincronização (segundos desde 1970), para a tela mostrar e decidir se sincroniza sozinha.
    nonisolated static let chaveUltimaSync = "ultimaSincronizacaoBanco"
    /// Quanto do passado buscar. Toda sincronização refaz a janela inteira: a Pluggy às vezes traz lançamentos
    /// com data antiga depois (cartão, conexão que ainda estava carregando), e uma busca só dos últimos dias perdia esses.
    /// O Open Finance guarda 12 meses.
    private static let diasBuscados = 365

    static var configurado: Bool { CredenciaisPluggy.salvas != nil }

    nonisolated static func separarItens(_ texto: String) -> [String] {
        texto.split(whereSeparator: { $0 == "," || $0.isNewline || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Confere as credenciais e devolve o nome de cada banco conectado.
    static func testar(_ c: CredenciaisPluggy) async throws -> [String] {
        let api = try await PluggyClient.entrar(c)
        var nomes: [String] = []
        for item in c.itens {
            let info = try await api.item(item)
            nomes.append(info["connector"]?["name"]?.string ?? item)
        }
        return nomes
    }

    /// Busca as transações novas e guarda no banco local. Devolve quantas entraram pela primeira vez.
    @discardableResult
    static func sincronizar(context: ModelContext) async throws -> Int {
        guard let c = CredenciaisPluggy.salvas else { throw FalhaFerramenta("Configura o Meu Pluggy nos Ajustes primeiro.") }
        let cal = Calendar.current
        let inicio = cal.startOfDay(for: cal.date(byAdding: .day, value: -diasBuscados, to: .now)!)

        let api = try await PluggyClient.entrar(c)
        var recebidas: [Transacao] = []
        for item in c.itens {
            let info = try await api.item(item)
            if let status = info["status"]?.string, status == "LOGIN_ERROR" {
                let nome = info["connector"]?["name"]?.string ?? item
                throw FalhaFerramenta("A conexão com \(nome) expirou. Renova no Meu Pluggy.")
            }
            for conta in try await api.contas(item: item) {
                guard let contaID = conta["id"]?.string else { continue }
                let nomeConta = conta["marketingName"]?.string ?? conta["name"]?.string ?? "Conta"
                let cartao = conta["type"]?.string == "CREDIT"
                for t in try await api.transacoes(conta: contaID, desde: inicio) {
                    if let nova = converter(t, conta: nomeConta, cartao: cartao) { recebidas.append(nova) }
                }
            }
        }

        let doPeriodo = try context.fetch(FetchDescriptor<Transacao>(predicate: #Predicate { $0.data >= inicio }))
        var porChave: [String: Transacao] = [:]
        for t in doPeriodo where t.doBanco { porChave[t.chave] = t }
        // A janela veio inteira, então o que sumiu da Pluggy sai daqui também
        // (pendentes mudam de id quando o banco confirma; a versão nova vem nesta busca).
        let chavesRecebidas = Set(recebidas.map(\.chave))
        for t in porChave.values where !chavesRecebidas.contains(t.chave) {
            context.delete(t)
        }

        var novas = 0
        for r in recebidas {
            if let t = porChave[r.chave] {
                t.data = r.data
                t.descricao = r.descricao
                t.valor = r.valor
                t.categoria = r.categoria
                t.conta = r.conta
                t.pendente = r.pendente
            } else {
                context.insert(r)
                porChave[r.chave] = r
                novas += 1
            }
        }
        try context.save()
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: chaveUltimaSync)
        return novas
    }

    private static func converter(_ t: JSONValue, conta: String, cartao: Bool) -> Transacao? {
        guard let id = t["id"]?.string,
              let valor = t["amountInAccountCurrency"]?.double ?? t["amount"]?.double,
              let data = t["date"]?.string.flatMap(lerData) else { return nil }
        // Na conta, negativo é saída. No cartão a Pluggy inverte: compra vem positiva e pagamento ou estorno, negativo.
        // O campo `type` não é confiável no cartão (compra pode vir como CREDIT), então vale o sinal.
        let descricao = t["merchant"]?["name"]?.string ?? t["description"]?.string ?? "Sem descrição"
        return Transacao(
            chave: prefixo + id,
            data: data,
            descricao: descricao,
            valor: cartao ? -valor : valor,
            categoria: t["category"]?.string,
            conta: conta,
            pendente: t["status"]?.string == "PENDING"
        )
    }

    /// A Pluggy manda em UTC. Lançamentos sem horário chegam à meia-noite (ou 03:00, a meia-noite de Brasília)
    /// e viram o dia certo no fuso local; os com horário são convertidos de verdade.
    static func lerData(_ texto: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let semFracao = ISO8601DateFormatter()
        guard let instante = iso.date(from: texto) ?? semFracao.date(from: texto) else {
            return Formatos.dia.date(from: String(texto.prefix(10)))
        }
        let hora = texto.dropFirst(11).prefix(8)
        if hora == "00:00:00" || hora == "03:00:00" {
            return Formatos.dia.date(from: String(texto.prefix(10)))
        }
        return instante
    }
}

/// O que fica no Keychain para falar com a Pluggy.
struct CredenciaisPluggy {
    let clientID: String
    let clientSecret: String
    let itens: [String]

    static var salvas: CredenciaisPluggy? {
        let id = Keychain.ler(Keychain.contaPluggyID) ?? ""
        let segredo = Keychain.ler(Keychain.contaPluggySecret) ?? ""
        let itens = Banco.separarItens(Keychain.ler(Keychain.contaPluggyItens) ?? "")
        guard !id.isEmpty, !segredo.isEmpty, !itens.isEmpty else { return nil }
        return CredenciaisPluggy(clientID: id, clientSecret: segredo, itens: itens)
    }
}


/// Chamadas diretas à API da Pluggy (api.pluggy.ai).
struct PluggyClient {
    private let chaveAPI: String
    private static let base = URL(string: "https://api.pluggy.ai")!

    enum Erro: LocalizedError {
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .http(401, _), .http(403, _): "Client ID ou Secret da Pluggy inválidos. Confere nos Ajustes."
            case .http(404, _): "Item ID não encontrado na Pluggy. Confere nos Ajustes."
            case .http(429, _): "Muitas chamadas seguidas pra Pluggy. Espera um pouco."
            case .http(let status, let mensagem): "Erro \(status) da Pluggy: \(mensagem)"
            }
        }
    }

    /// A chave de acesso vale 2 horas; como a sincronização é rápida, pega uma nova a cada vez.
    static func entrar(_ c: CredenciaisPluggy) async throws -> PluggyClient {
        var pedido = URLRequest(url: base.appending(path: "auth"))
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "content-type")
        let corpo: JSONValue = ["clientId": .string(c.clientID), "clientSecret": .string(c.clientSecret)]
        pedido.httpBody = try JSONEncoder().encode(corpo)
        let resposta = try await executar(pedido)
        guard let chave = resposta["apiKey"]?.string else { throw Erro.http(0, "resposta sem apiKey") }
        return PluggyClient(chaveAPI: chave)
    }

    func item(_ id: String) async throws -> JSONValue {
        try await get("items/\(id)")
    }

    func contas(item: String) async throws -> [JSONValue] {
        try await get("accounts", [URLQueryItem(name: "itemId", value: item)])["results"]?.array ?? []
    }

    /// Todas as transações da conta desde a data, seguindo as páginas.
    func transacoes(conta: String, desde: Date) async throws -> [JSONValue] {
        var todas: [JSONValue] = []
        var depois: String?
        repeat {
            var params = [
                URLQueryItem(name: "accountId", value: conta),
                URLQueryItem(name: "dateFrom", value: Formatos.dia.string(from: desde)),
            ]
            if let depois { params.append(URLQueryItem(name: "after", value: depois)) }
            let pagina = try await get("v2/transactions", params)
            todas += pagina["results"]?.array ?? []
            // `next` é algo como "?accountId=...&after=<cursor>", ou null na última página.
            depois = pagina["next"]?.string.flatMap { link in
                URLComponents(string: link)?.queryItems?.first(where: { $0.name == "after" })?.value
            }
        } while depois != nil
        return todas
    }

    private func get(_ caminho: String, _ params: [URLQueryItem] = []) async throws -> JSONValue {
        var url = Self.base.appending(path: caminho)
        if !params.isEmpty { url.append(queryItems: params) }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 60
        pedido.setValue(chaveAPI, forHTTPHeaderField: "X-API-KEY")
        return try await Self.executar(pedido)
    }

    private static func executar(_ pedido: URLRequest) async throws -> JSONValue {
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = try? JSONDecoder().decode(JSONValue.self, from: dados)
            throw Erro.http(status, json?["message"]?.string ?? String(decoding: dados, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: dados)
    }
}
