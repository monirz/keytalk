import AVFoundation
import Speech

/// Streams microphone audio into Apple's speech recognizer. When the
/// device supports it, recognition runs on-device: no API key, no network.
final class Transcriber {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finish: ((String) -> Void)?

    static func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { done(status == .authorized && mic) }
            }
        }
    }

    func start() throws {
        cancel()
        latest = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        if #available(macOS 13, *) { req.addsPunctuation = true }
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result { self.latest = result.bestTranscription.formattedString }
                if result?.isFinal == true || error != nil { self.complete() }
            }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buf, _ in
            req?.append(buf)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and calls back once with the final transcript.
    func stop(_ done: @escaping (String) -> Void) {
        finish = done
        stopAudio()
        request?.endAudio()
        // The recognizer sometimes never sends isFinal. Use the last partial result.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.complete() }
    }

    func cancel() {
        finish = nil
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func complete() {
        guard let f = finish else { return }
        finish = nil
        task = nil
        request = nil
        f(latest.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
