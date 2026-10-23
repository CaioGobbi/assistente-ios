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
    @State private var permissao = UNAuthorizationStatus.notDetermined
    @Environment(\.scenePhase) private var fase
    @Environment(\.openURL) private var openURL

    private enum TesteChave: Equatable {
        case nenhum, testando, ok
        case falhou(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Você") {
                    TextField("Seu nome", text: $nome)
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
