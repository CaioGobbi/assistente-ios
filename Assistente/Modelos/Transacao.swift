import Foundation
import SwiftData

/// Um lançamento do banco: veio do Meu Pluggy ou de um extrato importado.
@Model
final class Transacao {
    /// "banco-<id da Pluggy>" ou "extrato-<...>". Evita duplicar ao sincronizar ou importar de novo.
    @Attribute(.unique) var chave: String
    var data: Date
    var descricao: String
    /// Negativo é saída (gasto), positivo é entrada.
    var valor: Double
    /// Categoria como veio do banco, em inglês na Pluggy. Extrato importado vem sem.
    var categoria: String?
    var conta: String
    var pendente: Bool

    init(chave: String, data: Date, descricao: String, valor: Double, categoria: String?, conta: String, pendente: Bool = false) {
        self.chave = chave
        self.data = data
        self.descricao = descricao
        self.valor = valor
        self.categoria = categoria
        self.conta = conta
        self.pendente = pendente
    }

    var doBanco: Bool { chave.hasPrefix(Banco.prefixo) }

    /// Pagar a fatura move dinheiro da conta pro cartão; as compras já contam no cartão.
    var pagamentoDeFatura: Bool {
        if categoria?.localizedCaseInsensitiveContains("credit card payment") == true { return true }
        let d = descricao.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return d.contains("pagamento de fatura") || d.contains("pagto fatura") || d.contains("pagamento recebido")
    }

    var gasto: Bool { valor < 0 && !pagamentoDeFatura }
    var entrada: Bool { valor > 0 && !pagamentoDeFatura }

    var categoriaExibida: String {
        guard let categoria, !categoria.isEmpty else { return "Sem categoria" }
        return Self.traducoes[categoria.lowercased()] ?? categoria
    }

    /// As categorias mais comuns da Pluggy. O que não estiver aqui aparece como veio.
    private static let traducoes: [String: String] = [
        "income": "Renda",
        "salary": "Salário",
        "transfers": "Transferências",
        "transfer - pix": "Pix",
        "transfer - ted": "TED",
        "same person transfer": "Entre suas contas",
        "food and drinks": "Comida e bebida",
        "eating out": "Restaurantes",
        "groceries": "Mercado",
        "food delivery": "Delivery",
        "shopping": "Compras",
        "online shopping": "Compras online",
        "clothing": "Roupas",
        "electronics": "Eletrônicos",
        "transportation": "Transporte",
        "taxi and ride-hailing": "Táxi e apps",
        "public transportation": "Transporte público",
        "gas stations": "Combustível",
        "parking": "Estacionamento",
        "housing": "Moradia",
        "rent": "Aluguel",
        "utilities": "Contas da casa",
        "electricity": "Luz",
        "water": "Água",
        "telecommunications": "Telefone e internet",
        "internet": "Internet",
        "mobile": "Celular",
        "health": "Saúde",
        "pharmacy": "Farmácia",
        "leisure": "Lazer",
        "entertainment": "Entretenimento",
        "video streaming": "Streaming",
        "music streaming": "Música",
        "digital services": "Serviços digitais",
        "services": "Serviços",
        "education": "Educação",
        "travel": "Viagem",
        "taxes": "Impostos",
        "bank fees": "Tarifas bancárias",
        "interests charged": "Juros",
        "insurance": "Seguros",
        "investments": "Investimentos",
        "loans": "Empréstimos",
        "credit card payment": "Pagamento de fatura",
        "gaming": "Jogos",
        "gyms and fitness centers": "Academia",
        "pets": "Pets",
        "donations": "Doações",
    ]
}

/// Os números de um período, do jeito que a tela Gastos e o assistente enxergam.
struct ResumoGastos {
    struct Grupo: Identifiable {
        let nome: String
        let total: Double
        let quantidade: Int
        var id: String { nome }
    }

    let inicio: Date
    let fim: Date
    /// Do período, mais recentes primeiro.
    let transacoes: [Transacao]
    let totalGasto: Double
    let totalEntrada: Double
    /// Gastos por categoria, do maior pro menor. Totais positivos.
    let porCategoria: [Grupo]

    /// `fim` é exclusivo.
    init(_ todas: [Transacao], de inicio: Date, ate fim: Date) {
        self.inicio = inicio
        self.fim = fim
        let doPeriodo = todas.filter { $0.data >= inicio && $0.data < fim }.sorted { $0.data > $1.data }
        transacoes = doPeriodo
        let gastos = doPeriodo.filter(\.gasto)
        totalGasto = -gastos.reduce(0) { $0 + $1.valor }
        totalEntrada = doPeriodo.filter(\.entrada).reduce(0) { $0 + $1.valor }
        porCategoria = Dictionary(grouping: gastos, by: \.categoriaExibida)
            .map { Grupo(nome: $0.key, total: -$0.value.reduce(0) { $0 + $1.valor }, quantidade: $0.value.count) }
            .sorted { $0.total > $1.total }
    }

    var dias: Int {
        // Hoje conta como dia inteiro, mesmo que ainda não tenha acabado.
        max(1, Int((min(fim, .now).timeIntervalSince(inicio) / 86_400).rounded(.up)))
    }

    var mediaPorDia: Double { totalGasto / Double(dias) }
}
