import Foundation
import Clips
import Transcript
import Voz

public struct WorkProgress: Sendable {
    public let message: String
    public let fraction: Double?

    public init(_ message: String, fraction: Double? = nil) {
        self.message = message
        self.fraction = fraction
    }
}

public struct Selection: Sendable {
    public let transcript: String
    public let clips: [ClipResult]
}

/// One reusable model instance per studio. All inference stays off the UI actor.
public actor ClipperEngine {
    private let selector = Clips()
    private var transcriber: Voz?

    public init() {}

    public static var supportedLanguages: [String] { Voz.supportedLanguages.sorted() }

    public func availability() -> (clips: Bool, transcription: Bool) {
        (selector.isDownloaded(), Voz.isDownloaded())
    }

    public func prepare(
        includeTranscription: Bool,
        progress: @Sendable @escaping (WorkProgress) -> Void
    ) async throws {
        progress(WorkProgress("Preparing Clips. First use can take a few minutes."))
        try await selector.download { fraction in
            progress(WorkProgress(fraction < 1 ? "Downloading Clips" : "Loading Clips on this device", fraction: fraction < 1 ? fraction : nil))
        }
        try Task.checkCancellation()
        if includeTranscription {
            _ = try await loadTranscriber(progress: progress)
        }
    }

    public func select(
        text: String, limit: Int,
        progress: @Sendable @escaping (WorkProgress) -> Void
    ) async throws -> Selection {
        let sentences = TranscriptInput.sentences(from: text)
        guard sentences.count >= 3 else { throw ClipperError.tooFewSentences }
        try await prepare(includeTranscription: false, progress: progress)
        progress(WorkProgress("Finding the strongest moments"))
        let clips = try await selector.clips(in: sentences, limit: max(1, min(limit, 30)))
        try Task.checkCancellation()
        return Selection(transcript: sentences.joined(separator: "\n"), clips: try clips.map { try ClipResult(clip: $0) })
    }

    public func select(
        recording: URL, language: String, limit: Int,
        progress: @Sendable @escaping (WorkProgress) -> Void
    ) async throws -> Selection {
        guard Voz.supportedLanguages.contains(language) else { throw ClipperError.unsupportedLanguage }
        progress(WorkProgress("Reading the recording's audio"))
        // Voz reads audio files. Extract video audio explicitly rather than passing a movie to AVAudioFile.
        let audio = try await MediaExporter.audioForTranscription(from: recording)
        defer { try? FileManager.default.removeItem(at: audio) }
        let recognizer = try await loadTranscriber(progress: progress)
        progress(WorkProgress("Transcribing on this device"))
        let result = try await recognizer.transcribe(audio) { update in
            progress(WorkProgress("Transcribing on this device", fraction: update.fractionCompleted))
        }
        try Task.checkCancellation()
        // Voz.Word has no leading spaces; Transcript.TimedWord preserves input whitespace.
        let words = result.words.map { TimedWord(text: " " + $0.text, start: $0.start, end: $0.end) }
        let sentences = Sentence.sentences(from: words)
        guard sentences.count >= 3 else { throw ClipperError.tooFewSentences }
        try await prepare(includeTranscription: false, progress: progress)
        progress(WorkProgress("Finding the strongest moments"))
        let clips = try await selector.clips(in: sentences.map(\.text), limit: max(1, min(limit, 30)))
        try Task.checkCancellation()
        return Selection(
            transcript: sentences.map(\.text).joined(separator: "\n"),
            clips: try clips.map { try ClipResult(clip: $0, sentences: sentences, duration: result.duration) }
        )
    }

    private func loadTranscriber(
        progress: @Sendable @escaping (WorkProgress) -> Void
    ) async throws -> Voz {
        if let transcriber { return transcriber }
        progress(WorkProgress("Preparing the recording transcriber"))
        if !Voz.isDownloaded() {
            try await Voz.download { update in
                progress(WorkProgress("Downloading the recording transcriber", fraction: update.fraction))
            }
        }
        progress(WorkProgress("Loading the transcriber on this device"))
        let loaded = try await Voz()
        transcriber = loaded
        return loaded
    }
}
