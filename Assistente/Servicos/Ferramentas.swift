import Foundation
import SwiftData

/// Ferramentas que o Claude usa para ler e mexer nas tarefas e consultar os gastos.
@MainActor
struct Ferramentas {
    let context: ModelContext

    // MARK: Definições enviadas à API

    private static let camposTarefa: [String: JSONValue] = [
        "titulo": ["type": "string"],
        "data": ["type": "string", "description": "Dia no formato AAAA-MM-DD."],
        "hora": ["type": "string", "description": "Horário no formato HH:mm (24h). Sem data, vale para hoje."],
        "duracao_minutos": ["type": "integer", "description": "Estimativa de duração."],
        "prioridade": ["type": "string", "enum": .array(Prioridade.allCases.map { .string($0.chave) })],
        "recorrencia": ["type": "string", "enum": .array(Recorrencia.allCases.map { .string($0.rawValue) })],
        "notas": ["type": "string"],
    ]

    static let definicoes: [JSONValue] = [
        [
            "name": "listar_tarefas",
            "description": "Lista as tarefas pendentes (atrasadas, de hoje, futuras e sem data) e as concluídas hoje. Use antes de falar da agenda ou planejar.",
            "input_schema": ["type": "object", "properties": .object([:])],
        ],
        [
            "name": "criar_tarefa",
            "description": "Cria uma tarefa. Sem data, fica em 'sem data'.",
            "input_schema": ["type": "object", "properties": .object(camposTarefa), "required": ["titulo"]],
        ],
        [
            "name": "atualizar_tarefa",
            "description": "Altera campos de uma tarefa existente (reagendar, renomear, mudar prioridade...). Mande só o que muda. sem_data=true remove a data.",
            "input_schema": [
                "type": "object",
                "properties": .object(camposTarefa.merging(["id": ["type": "string"], "sem_data": ["type": "boolean"]]) { a, _ in a }),
                "required": ["id"],
            ],
        ],
        [
            "name": "concluir_tarefa",
            "description": "Marca uma tarefa como feita. Se repete, a próxima é criada sozinha.",
            "input_schema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]],
        ],
        [
            "name": "excluir_tarefa",
            "description": "Apaga uma tarefa de vez. Só use se o usuário pedir para apagar ou desistir dela.",
            "input_schema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]],
        ],
        [
            "name": "lembrar",
            "description": "Guarda um fato duradouro sobre o usuário (rotina, preferência, meta, pessoa). Um fato curto por chamada.",
            "input_schema": ["type": "object", "properties": ["texto": ["type": "string"]], "required": ["texto"]],
        ],
        [
            "name": "esquecer",
            "description": "Apaga um fato da memória que mudou ou ficou desatualizado, pelo id mostrado na memória.",
            "input_schema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]],
        ],
        [
            "name": "consultar_gastos",
            "description": "Resume as transações do banco num período: total gasto, entradas, gastos por categoria, maiores gastos e a lista de lançamentos. Valores negativos são saídas. Sem datas, pega os últimos 30 dias.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "de": ["type": "string", "description": "Primeiro dia, AAAA-MM-DD."],
                    "ate": ["type": "string", "description": "Último dia (incluso), AAAA-MM-DD."],
                    "busca": ["type": "string", "description": "Filtra por texto na descrição, categoria ou conta (ex.: ifood, uber, mercado)."],
                ],
            ],
        ],
    ]

    // MARK: Execução

    func executar(nome: String, entrada: JSONValue) -> (texto: String, erro: Bool) {
        do {
            let saida: JSONValue
            switch nome {
            case "listar_tarefas": saida = try listar()
            case "criar_tarefa": saida = try criar(entrada)
            case "atualizar_tarefa": saida = try atualizar(entrada)
            case "concluir_tarefa": saida = try concluir(entrada)
            case "excluir_tarefa": saida = try excluir(entrada)
            case "lembrar": saida = try lembrar(entrada)
            case "esquecer": saida = try esquecer(entrada)
            case "consultar_gastos": saida = try consultarGastos(entrada)
            default: throw FalhaFerramenta("Ferramenta desconhecida: \(nome)")
            }
            try context.save()
            return (saida.textoJSON, false)
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private func listar() throws -> JSONValue {
        let agenda = Agenda(try context.fetch(FetchDescriptor<Tarefa>()))
        return [
            "atrasadas": .array(agenda.atrasadas.map(resumo)),
            "hoje": .array(agenda.hoje.map(resumo)),
            "proximas": .array(agenda.proximas.map(resumo)),
            "sem_data": .array(agenda.semData.map(resumo)),
            "concluidas_hoje": .array(agenda.feitasHoje.map(resumo)),
        ]
    }

    private func criar(_ e: JSONValue) throws -> JSONValue {
        let titulo = e["titulo"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !titulo.isEmpty else { throw FalhaFerramenta("Faltou o título.") }
        let quando = try Formatos.combinar(dia: e["data"]?.string, hora: e["hora"]?.string)
        let tarefa = Tarefa(
            titulo: titulo,
            notas: e["notas"]?.string ?? "",
            data: quando.data,
            temHorario: quando.temHorario,
            duracaoMinutos: e["duracao_minutos"]?.int,
            prioridade: try prioridade(e) ?? .normal,
            recorrencia: try recorrencia(e) ?? .nenhuma
        )
        context.insert(tarefa)
        return ["criada": resumo(tarefa)]
    }

    private func atualizar(_ e: JSONValue) throws -> JSONValue {
        let t = try buscar(e)
        if let titulo = e["titulo"]?.string, !titulo.isEmpty { t.titulo = titulo }
        if let notas = e["notas"]?.string { t.notas = notas }
        if let duracao = e["duracao_minutos"]?.int { t.duracaoMinutos = duracao > 0 ? duracao : nil }
        if let p = try prioridade(e) { t.prioridade = p }
        if let r = try recorrencia(e) { t.recorrencia = r }
        if e["sem_data"]?.bool == true {
            t.data = nil
            t.temHorario = false
        } else if e["data"] != nil || e["hora"] != nil {
            // O que não veio na chamada continua como estava.
            let dia = e["data"]?.string ?? t.data.map { Formatos.dia.string(from: $0) }
            let hora = e["hora"]?.string ?? (t.temHorario ? t.data.map { Formatos.hora.string(from: $0) } : nil)
            let quando = try Formatos.combinar(dia: dia, hora: hora)
            t.data = quando.data
            t.temHorario = quando.temHorario
        }
        return ["atualizada": resumo(t)]
    }

    private func concluir(_ e: JSONValue) throws -> JSONValue {
        let t = try buscar(e)
        var saida: [String: JSONValue] = ["concluida": resumo(t)]
        if let proxima = t.concluir(em: context) { saida["proxima_ocorrencia"] = resumo(proxima) }
        return .object(saida)
    }

    private func excluir(_ e: JSONValue) throws -> JSONValue {
        let t = try buscar(e)
        let titulo = t.titulo
        context.delete(t)
        return ["excluida": .string(titulo)]
    }

    private func lembrar(_ e: JSONValue) throws -> JSONValue {
        let texto = e["texto"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !texto.isEmpty else { throw FalhaFerramenta("Faltou o texto.") }
        let lembranca = Lembranca(texto: texto)
        context.insert(lembranca)
        return ["guardado": .string(lembranca.id.uuidString)]
    }

    private func esquecer(_ e: JSONValue) throws -> JSONValue {
        guard let texto = e["id"]?.string, let alvo = UUID(uuidString: texto) else { throw FalhaFerramenta("id inválido.") }
        var descritor = FetchDescriptor<Lembranca>(predicate: #Predicate { $0.id == alvo })
        descritor.fetchLimit = 1
        guard let lembranca = try context.fetch(descritor).first else { throw FalhaFerramenta("Esse fato não existe.") }
        context.delete(lembranca)
        return ["esquecido": .string(texto)]
    }

    private static let limiteLancamentos = 150

    private func consultarGastos(_ e: JSONValue) throws -> JSONValue {
        let cal = Calendar.current
        let hoje = cal.startOfDay(for: .now)
        let inicio = try e["de"]?.string.map(diaGastos) ?? cal.date(byAdding: .day, value: -29, to: hoje)!
        let ultimo = try e["ate"]?.string.map(diaGastos) ?? hoje
        let fim = cal.date(byAdding: .day, value: 1, to: ultimo)!

        var todas = try context.fetch(FetchDescriptor<Transacao>(predicate: #Predicate { $0.data >= inicio && $0.data < fim }))
        if let busca = e["busca"]?.string?.trimmingCharacters(in: .whitespaces), !busca.isEmpty {
            todas = todas.filter {
                $0.descricao.localizedCaseInsensitiveContains(busca)
                    || $0.categoriaExibida.localizedCaseInsensitiveContains(busca)
                    || $0.conta.localizedCaseInsensitiveContains(busca)
            }
        }
        let r = ResumoGastos(todas, de: inicio, ate: fim)
        let ultimaSync = UserDefaults.standard.double(forKey: Banco.chaveUltimaSync)
        let categorias: [JSONValue] = r.porCategoria.map { g in
            ["categoria": .string(g.nome), "total": .number(arredondar(g.total)), "quantidade": .number(Double(g.quantidade))]
        }
        let maiores = r.transacoes.filter(\.gasto).sorted { $0.valor < $1.valor }.prefix(10)


        var saida: [String: JSONValue] = [
            "periodo": .string("\(Formatos.dia.string(from: inicio)) a \(Formatos.dia.string(from: ultimo))"),
            "total_gasto": .number(arredondar(r.totalGasto)),
            "total_entradas": .number(arredondar(r.totalEntrada)),
            "media_gasto_por_dia": .number(arredondar(r.mediaPorDia)),
            "quantidade_lancamentos": .number(Double(r.transacoes.count)),
            "por_categoria": .array(categorias),
            "maiores_gastos": .array(maiores.map(lancamento)),
            "lancamentos": .array(r.transacoes.prefix(Self.limiteLancamentos).map(lancamento)),
            "obs": "Pagamentos de fatura do cartão ficam fora dos totais para não contar a mesma compra duas vezes.",
        ]
        if r.transacoes.count > Self.limiteLancamentos {
            saida["lancamentos_omitidos"] = .number(Double(r.transacoes.count - Self.limiteLancamentos))
        }
        if ultimaSync > 0 {
            saida["banco_sincronizado_em"] = .string(Formatos.agora(Date(timeIntervalSince1970: ultimaSync)))
        }
        if r.transacoes.isEmpty {
            saida["aviso"] = "Nenhuma transação nesse período. O usuário pode conectar o banco (Meu Pluggy) ou importar um extrato na aba Gastos."
        }
        return .object(saida)
    }

    private func diaGastos(_ texto: String) throws -> Date {
        guard let d = Formatos.dia.date(from: texto) else { throw FalhaFerramenta("Data inválida '\(texto)'. Use AAAA-MM-DD.") }
        return Calendar.current.startOfDay(for: d)
    }

    private func lancamento(_ t: Transacao) -> JSONValue {
        var o: [String: JSONValue] = [
            "data": .string(Formatos.dia.string(from: t.data)),
            "descricao": .string(t.descricao),
            "valor": .number(arredondar(t.valor)),
            "categoria": .string(t.categoriaExibida),
            "conta": .string(t.conta),
        ]
        if t.pendente { o["pendente"] = true }
        if t.pagamentoDeFatura { o["pagamento_de_fatura"] = true }
        return .object(o)
    }

    private func arredondar(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    // MARK: Apoio

    private func buscar(_ e: JSONValue) throws -> Tarefa {
        guard let texto = e["id"]?.string, let alvo = UUID(uuidString: texto) else {
            throw FalhaFerramenta("id inválido. Use o id que veio de listar_tarefas.")
        }
        var descritor = FetchDescriptor<Tarefa>(predicate: #Predicate { $0.id == alvo })
        descritor.fetchLimit = 1
        guard let t = try context.fetch(descritor).first else { throw FalhaFerramenta("Tarefa \(texto) não existe.") }
        return t
    }

    private func prioridade(_ e: JSONValue) throws -> Prioridade? {
        guard let chave = e["prioridade"]?.string else { return nil }
        guard let p = Prioridade(chave: chave) else { throw FalhaFerramenta("Prioridade inválida: \(chave)") }
        return p
    }

    private func recorrencia(_ e: JSONValue) throws -> Recorrencia? {
        guard let chave = e["recorrencia"]?.string else { return nil }
        guard let r = Recorrencia(rawValue: chave) else { throw FalhaFerramenta("Recorrência inválida: \(chave)") }
        return r
    }

    private func resumo(_ t: Tarefa) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(t.id.uuidString),
            "titulo": .string(t.titulo),
            "prioridade": .string(t.prioridade.chave),
        ]
        if let d = t.data {
            o["data"] = .string(Formatos.dia.string(from: d))
            if t.temHorario { o["hora"] = .string(Formatos.hora.string(from: d)) }
        }
        if let m = t.duracaoMinutos { o["duracao_minutos"] = .number(Double(m)) }
        if t.recorrencia != .nenhuma { o["recorrencia"] = .string(t.recorrencia.rawValue) }
        if !t.notas.isEmpty { o["notas"] = .string(t.notas) }
        return .object(o)
    }
}
