import Foundation
import SwiftData

/// Lê um extrato exportado do banco (OFX ou CSV) e guarda as transações.
@MainActor
enum Extrato {
    struct Linha {
        let chave: String
        let data: Date
        let descricao: String
        let valor: Double
    }

    /// Devolve quantas transações eram novas. Importar o mesmo arquivo de novo não duplica.
    static func importar(_ url: URL, context: ModelContext) throws -> Int {
        let acesso = url.startAccessingSecurityScopedResource()
        defer { if acesso { url.stopAccessingSecurityScopedResource() } }
        let dados = try Data(contentsOf: url)
        // Banco brasileiro ainda exporta muito em Latin-1.
        guard let texto = String(data: dados, encoding: .utf8)
                ?? String(data: dados, encoding: .windowsCP1252)
                ?? String(data: dados, encoding: .isoLatin1) else {
            throw FalhaFerramenta("Não consegui ler esse arquivo.")
        }
        let conta = url.deletingPathExtension().lastPathComponent
        let linhas = texto.range(of: "<STMTTRN>", options: .caseInsensitive) != nil ? try ofx(texto) : try csv(texto)
        guard !linhas.isEmpty else { throw FalhaFerramenta("Não achei nenhuma transação nesse arquivo.") }

        let existentes = Set(try context.fetch(FetchDescriptor<Transacao>()).map(\.chave))
        var novas = 0
        for l in linhas where !existentes.contains(l.chave) {
            context.insert(Transacao(chave: l.chave, data: l.data, descricao: l.descricao, valor: l.valor,
                                     categoria: nil, conta: conta))
            novas += 1
        }
        try context.save()
        return novas
    }

    // MARK: OFX

    static func ofx(_ texto: String) throws -> [Linha] {
        let conta = campo("ACCTID", em: texto) ?? ""
        var linhas: [Linha] = []
        var resto = texto[...]
        while let abre = resto.range(of: "<STMTTRN>", options: .caseInsensitive) {
            let fim = resto.range(of: "</STMTTRN>", options: .caseInsensitive, range: abre.upperBound..<resto.endIndex)
            let bloco = String(resto[abre.upperBound..<(fim?.lowerBound ?? resto.endIndex)])
            resto = resto[(fim?.upperBound ?? resto.endIndex)...]

            guard let quando = campo("DTPOSTED", em: bloco).flatMap({ diaOFX.date(from: String($0.prefix(8))) }),
                  let valor = campo("TRNAMT", em: bloco).flatMap(numero) else { continue }
            let memo = campo("MEMO", em: bloco)
            let nome = campo("NAME", em: bloco)
            let descricao = [nome, memo].compactMap { $0 }.first { !$0.isEmpty } ?? "Sem descrição"
            let id = campo("FITID", em: bloco) ?? "\(Formatos.dia.string(from: quando))|\(valor)|\(descricao)"
            linhas.append(Linha(chave: "extrato-ofx-\(conta)-\(id)", data: quando, descricao: descricao, valor: valor))
        }
        return linhas
    }

    /// OFX é SGML: `<TAG>valor` sem fechar, ou `<TAG>valor</TAG>`.
    private static func campo(_ tag: String, em texto: String) -> String? {
        guard let r = texto.range(of: "<\(tag)>", options: .caseInsensitive) else { return nil }
        let depois = texto[r.upperBound...]
        let fim = depois.firstIndex { $0 == "<" || $0.isNewline } ?? depois.endIndex
        let valor = depois[..<fim].trimmingCharacters(in: .whitespaces)
        return valor.isEmpty ? nil : valor
    }

    private static let diaOFX: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    // MARK: CSV

    /// Procura as colunas de data, descrição e valor pelo cabeçalho (Nubank, Inter, planilhas genéricas).
    static func csv(_ texto: String) throws -> [Linha] {
        let brutas = texto.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let cabecalho = brutas.first else { return [] }
        let separador: Character = cabecalho.filter { $0 == ";" }.count > cabecalho.filter { $0 == "," }.count ? ";" : ","
        let colunas = celulas(cabecalho, separador).map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        func coluna(_ nomes: [String]) -> Int? {
            colunas.firstIndex { c in nomes.contains { c.contains($0) } }
        }
        guard let iData = coluna(["data", "date"]),
              let iValor = coluna(["valor", "amount", "quantia"]),
              let iDescricao = coluna(["descri", "title", "histor", "lancamento", "estabelecimento", "memo"]) else {
            throw FalhaFerramenta("Não reconheci as colunas do CSV. Ele precisa ter data, descrição e valor.")
        }
        // No CSV do cartão do Nubank (date,title,amount) compra vem positiva.
        let compraPositiva = colunas.contains("title") && colunas.contains("amount")

        var linhas: [Linha] = []
        var repetidas: [String: Int] = [:]
        for bruta in brutas.dropFirst() {
            let c = celulas(bruta, separador)
            guard c.indices.contains(iData), c.indices.contains(iValor), c.indices.contains(iDescricao),
                  let quando = dataCSV(c[iData]), var valor = numero(c[iValor]) else { continue }
            if compraPositiva { valor = -valor }
            let descricao = c[iDescricao].isEmpty ? "Sem descrição" : c[iDescricao]
            // Duas compras iguais no mesmo dia são duas compras; o contador separa uma da outra.
            let base = "\(Formatos.dia.string(from: quando))|\(valor)|\(descricao)"
            let n = repetidas[base, default: 0]
            repetidas[base] = n + 1
            linhas.append(Linha(chave: "extrato-csv-\(base)|\(n)", data: quando, descricao: descricao, valor: valor))
        }
        return linhas
    }

    private static func celulas(_ linha: String, _ separador: Character) -> [String] {
        var saida: [String] = []
        var atual = ""
        var entreAspas = false
        for ch in linha {
            if ch == "\"" { entreAspas.toggle() }
            else if ch == separador && !entreAspas { saida.append(atual); atual = "" }
            else { atual.append(ch) }
        }
        saida.append(atual)
        return saida.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func dataCSV(_ texto: String) -> Date? {
        let t = String(texto.prefix(10))
        // "15/10/24" lido como dd/MM/yyyy viraria o ano 24; o tamanho decide o formato.
        let formatos = t.count == 8 ? ["dd/MM/yy"] : ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy"]
        for formato in formatos {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = formato
            f.isLenient = false
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    /// Aceita "-12.50", "1.234,56", "R$ -45,00".
    static func numero(_ texto: String) -> Double? {
        var t = texto.replacingOccurrences(of: "R$", with: "").filter { !$0.isWhitespace }
        let virgula = t.lastIndex(of: ",")
        let ponto = t.lastIndex(of: ".")
        if let virgula, ponto == nil || virgula > ponto! {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        return Double(t)
    }
}
