import SwiftUI
import UIKit

/// Visual do Tomoshibi: fundo creme, títulos serifados (New York) e o âmbar da chama como único destaque.
enum Tema {
    static let fundo = cor(0xFAF8F3, escuro: 0x141311)
    static let cartao = cor(0xFFFFFF, escuro: 0x1E1C19)
    static let tinta = cor(0x1C1A17, escuro: 0xF2EEE6)
    static let suave = cor(0x6B665E, escuro: 0xA39D92)
    static let linha = cor(0xE4DFD4, escuro: 0x34302A)
    static let campo = cor(0xF3EFE7, escuro: 0x2A2723)
    static let destaque = cor(0xC2571A, escuro: 0xF08A4B)
    static let positivo = cor(0x2F6B3C, escuro: 0x7BC08A)
    static let negativo = cor(0xB3261E, escuro: 0xF2867E)
    /// A barra de abas é escura nos dois modos.
    static let barra = cor(0x1C1A17, escuro: 0x2A2723)
    static let barraAtiva = cor(0x3A3631, escuro: 0x45403A)
    static let barraIcone = cor(0xA39D92, escuro: 0x8F897E)
    static let barraIconeAtivo = cor(0xFAF8F3, escuro: 0xF2EEE6)

    /// Espaço que a barra de abas flutuante ocupa no rodapé.
    static let alturaBarra: CGFloat = 84

    static func titulo(_ tamanho: CGFloat) -> Font {
        .system(size: tamanho, weight: .regular, design: .serif)
    }

    /// Títulos de navegação (Ajustes, Memória, telas de edição) também em serifa.
    static func configurarAparencia() {
        let serif = { (tamanho: CGFloat, peso: UIFont.Weight) -> UIFont in
            let base = UIFont.systemFont(ofSize: tamanho, weight: peso)
            return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: tamanho)
        }
        let aparencia = UINavigationBarAppearance()
        aparencia.configureWithTransparentBackground()
        aparencia.backgroundColor = UIColor(fundo)
        aparencia.largeTitleTextAttributes = [.font: serif(34, .regular), .foregroundColor: UIColor(tinta)]
        aparencia.titleTextAttributes = [.font: serif(18, .medium), .foregroundColor: UIColor(tinta)]
        UINavigationBar.appearance().standardAppearance = aparencia
        UINavigationBar.appearance().scrollEdgeAppearance = aparencia
        UINavigationBar.appearance().compactAppearance = aparencia
    }

    private static func cor(_ claro: UInt32, escuro: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? escuro : claro
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Rótulo pequeno em caixa alta ("AGORA · 10:00").
struct Sobrescrito: View {
    let texto: String
    var cor: Color = Tema.suave

    var body: some View {
        Text(texto.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(cor)
    }
}

/// Cabeçalho de seção solto, sem as caixinhas do iOS.
struct TituloSecao: View {
    let texto: String
    var cor: Color = Tema.suave

    var body: some View {
        Text(texto)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(cor)
            .textCase(nil)
    }
}

/// Botão em pílula: cheio (ação principal) ou contornado.
struct BotaoPilula: ButtonStyle {
    var cheio = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .foregroundStyle(cheio ? Tema.fundo : Tema.tinta)
            .background(cheio ? Tema.tinta : Color.clear, in: Capsule())
            .overlay { if !cheio { Capsule().strokeBorder(Tema.linha) } }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Avatar do Tomoshibi: a chama da lamparina num círculo escuro.
struct AvatarChama: View {
    var tamanho: CGFloat = 40

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: tamanho * 0.48))
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.69, blue: 0.18), Color(red: 0.91, green: 0.27, blue: 0.12)],
                                            startPoint: .bottom, endPoint: .top))
            .frame(width: tamanho, height: tamanho)
            .background(Color(red: 0.11, green: 0.10, blue: 0.09), in: Circle())
            .accessibilityHidden(true)
    }
}

extension View {
    /// Cartão branco com sombra leve.
    func cartao(raio: CGFloat = 24, padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.cartao, in: RoundedRectangle(cornerRadius: raio, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }

    /// Linha de List sem fundo, sem separador e com as margens do layout.
    func linhaSolta(topo: CGFloat = 0, base: CGFloat = 0, inicio: CGFloat = 24) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: topo, leading: inicio, bottom: base, trailing: 24))
    }

    /// Lista no fundo creme, sem o cinza padrão.
    func fundoTomoshibi() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Tema.fundo)
    }
}
