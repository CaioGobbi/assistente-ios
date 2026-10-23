import AVFoundation
import Observation
import Speech

/// Ditado: transforma o que você fala em texto, no próprio iPhone quando possível.
/// O Claude recebe só o texto; o áudio não sai do aparelho.
@MainActor
@Observable
final class Ditado {
    enum Estado { case parado, ouvindo }

    private(set) var estado = Estado.parado
    private(set) var transcricao = ""
    var erro: String?

    @ObservationIgnored private let reconhecedor = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    @ObservationIgnored private let captura = CapturaDeVoz()
    @ObservationIgnored private var finalizado = false

    func comecar() async {
        guard estado == .parado else { return }
        erro = nil
        transcricao = ""
        finalizado = false
        guard await Self.permitido() else {
            erro = "Libera o microfone e o reconhecimento de fala em Ajustes do iPhone > 灯火."
            return
        }
        guard let reconhecedor, reconhecedor.isAvailable else {
            erro = "O reconhecimento de voz não está disponível agora."
            return
        }
        do {
            try captura.iniciar(reconhecedor: reconhecedor) { [weak self] texto, fim in
                Task { @MainActor in self?.receber(texto, fim: fim) }
            }
            estado = .ouvindo
        } catch {
            captura.cancelar()
            erro = "Não consegui abrir o microfone."
        }
    }

    /// Para de ouvir, espera o reconhecimento fechar a última frase e devolve o texto.
    func concluir() async -> String {
        if estado == .ouvindo {
            captura.pararAudio()
            for _ in 0..<20 where !finalizado {
                try? await Task.sleep(for: .milliseconds(100))
            }
            captura.encerrar()
        }
        let texto = transcricao.trimmingCharacters(in: .whitespacesAndNewlines)
        // Limpa antes de parar, para a tela não jogar o texto no campo.
        transcricao = ""
        estado = .parado
        return texto
    }

    func cancelar() {
        captura.cancelar()
        transcricao = ""
        estado = .parado
    }

    private func receber(_ texto: String?, fim: Bool) {
        if let texto { transcricao = texto }
        guard fim else { return }
        finalizado = true
        // O sistema encerrou sozinho (silêncio longo ou erro): para de ouvir e deixa o texto na tela.
        if estado == .ouvindo {
            captura.encerrar()
            estado = .parado
        }
    }

    private static func permitido() async -> Bool {
        let fala = await withCheckedContinuation { continuacao in
            SFSpeechRecognizer.requestAuthorization { continuacao.resume(returning: $0) }
        }
        guard fala == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

/// A parte de áudio fica fora do MainActor: os callbacks chegam em threads do sistema.
final class CapturaDeVoz: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarefa: SFSpeechRecognitionTask?

    func iniciar(
        reconhecedor: SFSpeechRecognizer,
        aoResultado: @escaping @Sendable (_ texto: String?, _ fim: Bool) -> Void
    ) throws {
        let sessao = AVAudioSession.sharedInstance()
        try sessao.setCategory(.record, mode: .measurement, options: .duckOthers)
        try sessao.setActive(true, options: .notifyOthersOnDeactivation)

        let pedido = SFSpeechAudioBufferRecognitionRequest()
        pedido.shouldReportPartialResults = true
        pedido.addsPunctuation = true
        if reconhecedor.supportsOnDeviceRecognition { pedido.requiresOnDeviceRecognition = true }

        let entrada = motor.inputNode
        entrada.installTap(onBus: 0, bufferSize: 1024, format: entrada.outputFormat(forBus: 0)) { buffer, _ in
            pedido.append(buffer)
        }
        motor.prepare()
        try motor.start()

        self.pedido = pedido
        tarefa = reconhecedor.recognitionTask(with: pedido) { resultado, erro in
            if let resultado {
                aoResultado(resultado.bestTranscription.formattedString, resultado.isFinal)
            } else if erro != nil {
                aoResultado(nil, true)
            }
        }
    }

    /// Para o microfone; o reconhecimento ainda termina a última frase.
    func pararAudio() {
        if motor.isRunning {
            motor.stop()
            motor.inputNode.removeTap(onBus: 0)
        }
        pedido?.endAudio()
    }

    func encerrar() {
        pararAudio()
        tarefa = nil
        pedido = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancelar() {
        tarefa?.cancel()
        encerrar()
    }
}

/// Lê em voz alta as respostas do Tomoshibi quando você mandou áudio.
@MainActor
@Observable
final class Leitor {
    private(set) var falando = false

    @ObservationIgnored private let sintetizador = AVSpeechSynthesizer()
    @ObservationIgnored private var ouvinte: Ouvinte?

    init() {
        let ouvinte = Ouvinte { [weak self] in self?.falando = false }
        sintetizador.delegate = ouvinte
        self.ouvinte = ouvinte
    }

    func falar(_ markdown: String) {
        let texto = markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        guard !texto.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        sintetizador.speak(frase)
        falando = true
    }

    func parar() {
        sintetizador.stopSpeaking(at: .immediate)
        falando = false
    }

    private final class Ouvinte: NSObject, AVSpeechSynthesizerDelegate {
        let aoTerminar: @MainActor () -> Void
        init(aoTerminar: @escaping @MainActor () -> Void) { self.aoTerminar = aoTerminar }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            guard !synthesizer.isSpeaking else { return }
            Task { @MainActor in aoTerminar() }
        }
    }
}
