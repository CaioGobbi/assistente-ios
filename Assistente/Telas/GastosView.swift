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
                    vazio
                } else {
                    Section { cabecalho(resumo) }
                    if let aviso { Section { avisoView(aviso) } }
                    categorias(resumo)
                    lancamentos(resumo)
                }
            }
            .navigationTitle("Gastos")
            .toolbar {
                Menu("Mais", systemImage: "ellipsis.circle") {
                    Button("Sincronizar banco", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await sincronizar() }
                    }
                    .disabled(!Banco.configurado || sincronizando)
                    Button("Importar extrato (OFX/CSV)", systemImage: "square.and.arrow.down") { importando = true }
                    Button("Configurar banco", systemImage: "gearshape", action: abrirAjustes)
                }
            }
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

    private var vazio: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Nenhum gasto ainda",
                systemImage: "creditcard",
                description: Text("Conecte seus bancos pelo Meu Pluggy ou importe um extrato OFX/CSV exportado do app do banco.")
            )
            if sincronizando { ProgressView("Buscando no banco…") }
            if let aviso { avisoView(aviso) }
            HStack {
                if Banco.configurado {
                    Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath") { Task { await sincronizar() } }
                        .disabled(sincronizando)
                } else {
                    Button("Conectar banco", systemImage: "building.columns", action: abrirAjustes)
                }
                Button("Importar extrato", systemImage: "square.and.arrow.down") { importando = true }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }

    private func cabecalho(_ r: ResumoGastos) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Período", selection: $periodo) {
                ForEach(Periodo.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 2) {
                Text("GASTOU").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Formatos.reais(r.totalGasto))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(Formatos.reais(r.mediaPorDia)) por dia · entrou \(Formatos.reais(r.totalEntrada))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Button(action: analisar) {
                Label("Analisar com o Claude", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if sincronizando {
                ProgressView("Buscando no banco…").font(.footnote)
            } else if ultimaSync > 0 {
                Text("Banco sincronizado \(Date(timeIntervalSince1970: ultimaSync).formatted(.relative(presentation: .named).locale(Locale(identifier: "pt_BR"))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: periodo)
    }

    @ViewBuilder
    private func categorias(_ r: ResumoGastos) -> some View {
        if !r.porCategoria.isEmpty {
            let maior = r.porCategoria.first?.total ?? 1
            Section("Por categoria") {
                ForEach(r.porCategoria.prefix(8)) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(g.nome)
                            Spacer()
                            Text(Formatos.reais(g.total)).monospacedDigit()
                        }
                        ProgressView(value: g.total, total: maior)
                            .tint(.orange)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func lancamentos(_ r: ResumoGastos) -> some View {
        let cal = Calendar.current
        let dias = Dictionary(grouping: r.transacoes) { cal.startOfDay(for: $0.data) }
        ForEach(dias.keys.sorted(by: >), id: \.self) { dia in
            Section(Formatos.rotulo(dia: dia)) {
                ForEach(dias[dia] ?? []) { t in
                    LinhaTransacao(transacao: t)
                        .swipeActions {
                            Button("Apagar", systemImage: "trash", role: .destructive) {
                                context.delete(t)
                                try? context.save()
                            }
                        }
                }
            }
        }
        if r.transacoes.isEmpty {
            Text("Nada nesse período.").foregroundStyle(.secondary)
        }
    }

    private func avisoView(_ a: Aviso) -> some View {
        Label(a.texto, systemImage: a.erro ? "exclamationmark.triangle" : "checkmark.circle")
            .font(.footnote)
            .foregroundStyle(a.erro ? Color.red : Color.secondary)
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
                Text(transacao.descricao).lineLimit(2)
                HStack(spacing: 6) {
                    Text(transacao.categoriaExibida)
                    Text("·")
                    Text(transacao.conta).lineLimit(1)
                    if transacao.pendente { Text("· pendente") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Formatos.reais(transacao.valor))
                .monospacedDigit()
                .foregroundStyle(transacao.entrada ? Color.green : transacao.pagamentoDeFatura ? Color.secondary : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }
}
