import SwiftUI
import UIKit
import UserNotifications

struct AjustesView: View {
    @AppStorage(Preferencias.chaveNome) private var nome = ""
    @AppStorage(Preferencias.chaveModelo) private var modelo = Preferencias.modeloPadrao
    @AppStorage(Preferencias.chaveBriefing) private var minutoBriefing = Preferencias.briefingPadrao
    @AppStorage(Preferencias.chaveCheckin) private var minutoCheckin = Preferencias.checkinPadrao
    @State private var chave = Keychain.ler(Keychain.contaAPI) ?? ""
    @State private var teste = TesteChave.nenhum
    @State private var pluggyID = Keychain.ler(Keychain.contaPluggyID) ?? ""
    @State private var pluggySecret = Keychain.ler(Keychain.contaPluggySecret) ?? ""
    @State private var pluggyItens = Keychain.ler(Keychain.contaPluggyItens) ?? ""
    @State private var testeBanco = TesteBanco.nenhum
    @State private var permissao = UNAuthorizationStatus.notDetermined
    @Environment(\.scenePhase) private var fase
    @Environment(\.openURL) private var openURL

    private enum TesteChave: Equatable {
        case nenhum, testando, ok
        case falhou(String)
    }

    private enum TesteBanco: Equatable {
        case nenhum, testando
        case ok([String])
        case falhou(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Você") {
                    TextField("Seu nome", text: $nome)
                    NavigationLink {
                        MemoriaView()
                    } label: {
                        Label("O que ele sabe de você", systemImage: "brain")
                    }
                }

                Section {
                    HStack {
                        SecureField("Chave da API (sk-ant-…)", text: $chave)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        estadoChave
                    }
                    Button("Testar chave", action: testarChave)
                        .disabled(chave.isEmpty || teste == .testando)
                    if case .falhou(let motivo) = teste {
                        Text(motivo).font(.footnote).foregroundStyle(.red)
                    }
                    Picker("Modelo", selection: $modelo) {
                        ForEach(Preferencias.modelos) { Text($0.nome).tag($0.id) }
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("A chave fica só no Keychain deste iPhone. Crie uma em console.anthropic.com. O uso é cobrado por lá.")
                }

                banco

                Section {
                    notificacoes
                    DatePicker("Resumo da manhã", selection: horario($minutoBriefing), displayedComponents: .hourAndMinute)
                    DatePicker("Check-in da noite", selection: horario($minutoCheckin), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Rotina")
                } footer: {
                    Text("Além disso, cada tarefa com horário avisa na hora.")
                }
            }
            .navigationTitle("Ajustes")
            .onChange(of: chave) { _, valor in
                Keychain.salvar(valor.trimmingCharacters(in: .whitespacesAndNewlines), conta: Keychain.contaAPI)
                teste = .nenhum
            }
            .onChange(of: pluggyID) { _, valor in salvarBanco(valor, Keychain.contaPluggyID) }
            .onChange(of: pluggySecret) { _, valor in salvarBanco(valor, Keychain.contaPluggySecret) }
            .onChange(of: pluggyItens) { _, valor in salvarBanco(valor, Keychain.contaPluggyItens) }
            .onChange(of: minutoBriefing) { Notificacoes.reagendarTudo() }
            .onChange(of: minutoCheckin) { Notificacoes.reagendarTudo() }
            .onChange(of: nome) { Notificacoes.reagendarTudo() }
            .task { await atualizarPermissao() }
            // Volta dos Ajustes do iPhone com a permissão talvez alterada.
            .onChange(of: fase) { _, nova in
                if nova == .active { Task { await atualizarPermissao() } }
            }
        }
    }

    @ViewBuilder
    private var estadoChave: some View {
        switch teste {
        case .testando:
            ProgressView()
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Chave válida")
        case .falhou:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Chave com problema")
        case .nenhum:
            EmptyView()
        }
    }

    private var banco: some View {
        Section {
            TextField("Client ID", text: $pluggyID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Client Secret", text: $pluggySecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Item IDs (separados por vírgula)", text: $pluggyItens, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Testar conexão", action: testarBanco)
                    .disabled(pluggyID.isEmpty || pluggySecret.isEmpty || pluggyItens.isEmpty || testeBanco == .testando)
                Spacer()
                if testeBanco == .testando { ProgressView() }
            }
            switch testeBanco {
            case .ok(let nomes):
                Label("Conectado: \(nomes.joined(separator: ", "))", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            case .falhou(let motivo):
                Text(motivo).font(.footnote).foregroundStyle(.red)
            default:
                EmptyView()
            }
        } header: {
            Text("Banco (Meu Pluggy)")
        } footer: {
            Text("No dashboard.pluggy.ai, crie uma aplicação e copie o Client ID e o Secret. Conecte seus bancos pelo Meu Pluggy e copie o Item ID de cada um. É Open Finance, só leitura, e tudo fica no Keychain deste iPhone.")
        }
    }

    private func salvarBanco(_ valor: String, _ conta: String) {
        Keychain.salvar(valor.trimmingCharacters(in: .whitespacesAndNewlines), conta: conta)
        testeBanco = .nenhum
    }

    private func testarBanco() {
        guard let credenciais = CredenciaisPluggy.salvas else { return }
        testeBanco = .testando
        Task {
            do {
                testeBanco = .ok(try await Banco.testar(credenciais))
            } catch {
                testeBanco = .falhou(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var notificacoes: some View {
        switch permissao {
        case .authorized, .provisional, .ephemeral:
            Label("Notificações ativadas", systemImage: "bell.badge.fill")
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Notificações desativadas", systemImage: "bell.slash.fill").foregroundStyle(.red)
                Text("Sem elas o resumo da manhã e os lembretes não chegam.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Abrir Ajustes do iPhone") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        default:
            Button("Permitir notificações", systemImage: "bell") {
                Task {
                    await Notificacoes.pedirPermissao()
                    await atualizarPermissao()
                    Notificacoes.reagendarTudo()
                }
            }
        }
    }

    private func atualizarPermissao() async {
        permissao = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func testarChave() {
        let valor = chave.trimmingCharacters(in: .whitespacesAndNewlines)
        teste = .testando
        Task {
            do {
                try await ClaudeClient.testar(chave: valor)
                teste = .ok
            } catch {
                teste = .falhou(error.localizedDescription)
            }
        }
    }

    private func horario(_ minutos: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutos.wrappedValue / 60, minute: minutos.wrappedValue % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: { data in
                let c = Calendar.current.dateComponents([.hour, .minute], from: data)
                minutos.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
