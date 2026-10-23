import SwiftUI

struct AjustesView: View {
    @AppStorage(Preferencias.chaveNome) private var nome = ""
    @AppStorage(Preferencias.chaveModelo) private var modelo = Preferencias.modeloPadrao
    @AppStorage(Preferencias.chaveBriefing) private var minutoBriefing = Preferencias.briefingPadrao
    @AppStorage(Preferencias.chaveCheckin) private var minutoCheckin = Preferencias.checkinPadrao
    @State private var chave = Keychain.ler(Keychain.contaAPI) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Você") {
                    TextField("Seu nome", text: $nome)
                }

                Section {
                    SecureField("Chave da API (sk-ant-…)", text: $chave)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Modelo", selection: $modelo) {
                        ForEach(Preferencias.modelos) { Text($0.nome).tag($0.id) }
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("A chave fica só no Keychain deste iPhone. Crie uma em console.anthropic.com. O uso é cobrado por lá.")
                }

                Section {
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
            }
            .onChange(of: minutoBriefing) { Notificacoes.reagendarTudo() }
            .onChange(of: minutoCheckin) { Notificacoes.reagendarTudo() }
            .onChange(of: nome) { Notificacoes.reagendarTudo() }
        }
    }

    private func horario(_ minutos: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let cal = Calendar.current
                return cal.date(bySettingHour: minutos.wrappedValue / 60, minute: minutos.wrappedValue % 60,
                                second: 0, of: .now) ?? .now
            },
            set: { data in
                let c = Calendar.current.dateComponents([.hour, .minute], from: data)
                minutos.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
