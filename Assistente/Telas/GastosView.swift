import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Pra onde vai o dinheiro: totais do período, categorias e os lançamentos dia a dia.
@MainActor
struct GastosView: View {
    var analisar: () -> Void
    var abrirAjustes: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Transacao.data, order: .reverse) private var transacoes: [Transacao]
    @AppStorage(Banco.chaveUltimaSync) private var ultimaSync: Double = 0
    @State private var periodo = Periodo.mes
    @State private var sincronizando = false
    @State private var importando = false
    @State private var aviso: Aviso?

    /// Sozinho, só sincroniza se a última vez foi há mais que isso.
    private static let intervaloAutomatico: TimeInterval = 6 * 3600

    private struct Aviso {
        let texto: String
        let erro: Bool
    }

    enum Periodo: String, CaseIterable, Identifiable {
        case semana = "7 dias"
        case mes = "Este mês"
        case trinta = "30 dias"

        var id: String { rawValue }

        func intervalo(cal: Calendar = .current) -> (inicio: Date, fim: Date) {
            let hoje = cal.startOfDay(for: .now)
            let amanha = cal.date(byAdding: .day, value: 1, to: hoje)!
            switch self {
            case .semana: return (cal.date(byAdding: .day, value: -6, to: hoje)!, amanha)
            case .mes: return (cal.dateInterval(of: .month, for: hoje)?.start ?? hoje, amanha)
            case .trinta: return (cal.date(byAdding: .day, value: -29, to: hoje)!, amanha)
            }
        }
    }

    var body: some View {
        let intervalo = periodo.intervalo()
        let resumo = ResumoGastos(transacoes, de: intervalo.inicio, ate: intervalo.fim)
        NavigationStack {
            List {
                if transacoes.isEmpty {
                    vazio.linhaSolta(topo: 40)
                } else {
                    cabecalho(resumo).linhaSolta(topo: 12, base: 20)
                    if let aviso { avisoView(aviso).linhaSolta(base: 12) }
                    categorias(resumo)
                    Button(action: analisar) {
                        Label("Onde dá pra economizar?", systemImage: "flame")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BotaoPilula(cheio: false))
                    .linhaSolta(topo: 4, base: 8)
                    lancamentos(resumo)
                }
            }
            .listStyle(.plain)
            .fundoTomoshibi()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Tema.alturaBarra) }
            .refreshable { await sincronizar() }
            .task { await sincronizarSePreciso() }
            .fileImporter(isPresented: $importando, allowedContentTypes: Self.tiposExtrato) { resultado in
                importar(resultado)
            }
        }
    }

    /// OFX não tem tipo próprio no iOS; `.data` deixa escolher o arquivo assim mesmo.
    private static let tiposExtrato: [UTType] = [.commaSeparatedText, .plainText, .data]

    // MARK: Partes

    private var maisOpcoes: some View {
        Menu {
            Button("Sincronizar banco", systemImage: "arrow.triangle.2.circlepath") {
                Task { await sincronizar() }
            }
            .disabled(!Banco.configurado || sincronizando)
            Button("Importar extrato (OFX/CSV)", systemImage: "square.and.arrow.down") { importando = true }
            Button("Configurar banco", systemImage: "gearshape", action: abrirAjustes)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Tema.suave)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Mais")
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pra onde vai o dinheiro")
                .font(Tema.titulo(30))
                .foregroundStyle(Tema.tinta)
            Text("Conecte seus bancos pelo Meu Pluggy ou importe um extrato OFX/CSV exportado do app do banco.")
                .foregroundStyle(Tema.suave)
            if sincronizando {
                ProgressView("Buscando no banco…").tint(Tema.destaque)
            }
            if let aviso { avisoView(aviso) }
            HStack(spacing: 8) {
                if Banco.configurado {
                    Button("Sincronizar") { Task { await sincronizar() } }
                        .buttonStyle(BotaoPilula())
                        .disabled(sincronizando)
                } else {
                    Button("Conectar banco", action: abrirAjustes)
                        .buttonStyle(BotaoPilula())
                }
                Button("Importar extrato") { importando = true }
                    .buttonStyle(BotaoPilula(cheio: false))
            }
        }
    }

    private func cabecalho(_ r: ResumoGastos) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                ForEach(Periodo.allCases) { p in
                    Button(p.rawValue) { periodo = p }
                        .buttonStyle(BotaoPilula(cheio: p == periodo))
                        .accessibilityAddTraits(p == periodo ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
                maisOpcoes.padding(.trailing, -10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Sobrescrito(texto: "Gastou · \(periodo.rawValue)")
                Text(Formatos.reais(r.totalGasto))
                    .font(Tema.titulo(44))
                    .foregroundStyle(Tema.tinta)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("\(Formatos.reais(r.mediaPorDia)) por dia · entrou \(Formatos.reais(r.totalEntrada))")
                    .font(.subheadline)
                    .foregroundStyle(Tema.suave)
            }
            .accessibilityElement(children: .combine)

            if sincronizando {
                ProgressView("Buscando no banco…").font(.footnote).tint(Tema.destaque)
            } else if ultimaSync > 0 {
                Text("Banco sincronizado \(Date(timeIntervalSince1970: ultimaSync).formatted(.relative(presentation: .named).locale(Locale(identifier: "pt_BR"))))")
                    .font(.caption)
                    .foregroundStyle(Tema.suave)
            }
        }
        .animation(.default, value: periodo)
    }

    /// Fatia da barra de categorias: as três maiores e o resto junto.
    private struct Fatia: Identifiable {
        let nome: String
        let total: Double
        let cor: Color
        var id: String { nome }
    }

    private func fatias(_ r: ResumoGastos) -> [Fatia] {
        let cores = [Tema.tinta, Tema.destaque, Color(red: 0.91, green: 0.66, blue: 0.47)]
        var lista = r.porCategoria.prefix(3).enumerated().map { i, g in Fatia(nome: g.nome, total: g.total, cor: cores[i]) }
        let resto = r.porCategoria.dropFirst(3).reduce(0) { $0 + $1.total }
        if resto > 0 { lista.append(Fatia(nome: "Outros", total: resto, cor: Tema.linha)) }
        return lista
    }

    @ViewBuilder
    private func categorias(_ r: ResumoGastos) -> some View {
        let lista = fatias(r)
        if !lista.isEmpty && r.totalGasto > 0 {
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { geo in
                    let espaco = CGFloat(lista.count - 1) * 2
                    HStack(spacing: 2) {
                        ForEach(lista) { f in
                            Rectangle()
                                .fill(f.cor)
                                .frame(width: max(2, (geo.size.width - espaco) * CGFloat(f.total / r.totalGasto)))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                .accessibilityHidden(true)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(lista) { f in
                        HStack(spacing: 8) {
                            Circle().fill(f.cor).frame(width: 8, height: 8)
                            Text(f.nome).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Formatos.reais(f.total)).monospacedDigit().foregroundStyle(Tema.suave)
                        }
                        .font(.footnote)
                        .foregroundStyle(Tema.tinta)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .linhaSolta(base: 16)
        }
    }

    @ViewBuilder
    private func lancamentos(_ r: ResumoGastos) -> some View {
        let cal = Calendar.current
        let dias = Dictionary(grouping: r.transacoes) { cal.startOfDay(for: $0.data) }
        ForEach(dias.keys.sorted(by: >), id: \.self) { dia in
            TituloSecao(texto: Formatos.rotulo(dia: dia))
                .linhaSolta(topo: 16, base: 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(dias[dia] ?? []) { t in
                LinhaTransacao(transacao: t)
                    .linhaSolta()
                    .swipeActions {
                        Button("Apagar", systemImage: "trash", role: .destructive) {
                            context.delete(t)
                            try? context.save()
                        }
                    }
            }
        }
        if r.transacoes.isEmpty {
            Text("Nada nesse período.").foregroundStyle(Tema.suave).linhaSolta(topo: 16)
        }
    }

    private func avisoView(_ a: Aviso) -> some View {
        Label(a.texto, systemImage: a.erro ? "exclamationmark.triangle" : "checkmark.circle")
            .font(.footnote)
            .foregroundStyle(a.erro ? Tema.negativo : Tema.suave)
    }

    // MARK: Ações

    private func sincronizarSePreciso() async {
        guard Date.now.timeIntervalSince1970 - ultimaSync > Self.intervaloAutomatico else { return }
        await sincronizar()
    }

    private func sincronizar() async {
        guard Banco.configurado, !sincronizando else { return }
        sincronizando = true
        defer { sincronizando = false }
        do {
            let novas = try await Banco.sincronizar(context: context)
            aviso = novas > 0 ? Aviso(texto: "\(novas) transações novas.", erro: false) : nil
        } catch {
            aviso = Aviso(texto: error.localizedDescription, erro: true)
        }
    }

    private func importar(_ resultado: Result<URL, Error>) {
        do {
            let novas = try Extrato.importar(try resultado.get(), context: context)
            aviso = Aviso(texto: novas == 0 ? "Esse extrato já estava importado." : "\(novas) transações importadas.", erro: false)
        } catch {
            aviso = Aviso(texto: error.localizedDescription, erro: true)
        }
    }
}

struct LinhaTransacao: View {
    let transacao: Transacao

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transacao.descricao).lineLimit(2).foregroundStyle(Tema.tinta)
                HStack(spacing: 6) {
                    Text(transacao.categoriaExibida)
                    Text("·")
                    Text(transacao.conta).lineLimit(1)
                    if transacao.pendente { Text("· pendente") }
                }
                .font(.footnote)
                .foregroundStyle(Tema.suave)
            }
            Spacer()
            Text(Formatos.reais(transacao.valor))
                .monospacedDigit()
                .foregroundStyle(transacao.entrada ? Tema.positivo : transacao.pagamentoDeFatura ? Tema.suave : Tema.tinta)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}
