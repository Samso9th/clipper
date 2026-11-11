import ClipperKit
import Foundation
import Observation

@MainActor @Observable
final class StudioModel {
    enum InputMode: String, CaseIterable { case recording = "Recording", transcript = "Transcript" }
    var mode = InputMode.recording
    var text = ""
    var limit = 5
    var language = "en"
    private(set) var recording: URL?
    private(set) var results: [ClipResult] = []
    private(set) var busy = false
    private(set) var status = "Import a recording to get started."
    private(set) var progress: Double?
    private(set) var clipsDownloaded = false
    private(set) var vozDownloaded = false
    private(set) var hasRun = false
    private(set) var exports: [Int: URL] = [:]
    private(set) var reel: URL?
    var error: String?
    private let engine = ClipperEngine()
    private var operationID = UUID()

    var canSelect: Bool {
        !busy && (mode == .recording ? recording != nil && language != "unsupported" : TranscriptInput.sentences(from: text).count >= 3)
    }

    func refreshAvailability() async {
        let state = await engine.availability()
        clipsDownloaded = state.clips
        vozDownloaded = state.transcription
    }

    func resetResults() {
        results = []
        exports = [:]
        reel = nil
        hasRun = false
    }

    func importRecording(_ url: URL) {
        run { [self] update in
            status = "Importing the recording to this device"
            let copied = try await MediaExporter.importRecording(from: url, progress: update)
            let previous = recording
            recording = copied
            resetResults()
            text = ""
            status = "Ready to find highlights."
            if let previous { try? FileManager.default.removeItem(at: previous.deletingLastPathComponent()) }
        }
    }

    func prepare() {
        let includeTranscription = mode == .recording
        run { [self] update in
            try await engine.prepare(includeTranscription: includeTranscription, progress: update)
            status = "Models are ready for offline use."
        }
    }

    func select() {
        guard canSelect else { return }
        let inputMode = mode
        let inputText = text
        let source = recording
        let budget = limit
        let spokenLanguage = language
        resetResults()
        run { [self] update in
            let selection: Selection
            if inputMode == .recording, let source {
                selection = try await engine.select(recording: source, language: spokenLanguage, limit: budget, progress: update)
            } else {
                selection = try await engine.select(text: inputText, limit: budget, progress: update)
            }
            results = selection.clips
            text = selection.transcript
            hasRun = true
            status = results.isEmpty ? "No moments were selected. Try a longer recording or transcript." : "\(results.count) moments ready to review."
        }
    }

    func export(_ clip: ClipResult) {
        guard let recording, !clip.ranges.isEmpty else { return }
        run { [self] _ in
            status = "Exporting moment \(clip.id + 1)"
            exports[clip.id] = try await MediaExporter.export(source: recording, ranges: clip.ranges)
            status = "Export ready. Use Save or share to keep it."
        }
    }

    func exportReel() {
        guard let recording, !results.isEmpty, results.allSatisfy({ !$0.ranges.isEmpty }) else { return }
        let ranges = results.flatMap(\.ranges)
        run { [self] _ in
            status = "Exporting the highlight reel, best moments first"
            reel = try await MediaExporter.export(source: recording, ranges: ranges)
            status = "Highlight reel ready. Use Save or share to keep it."
        }
    }

    private func run(_ operation: @escaping @MainActor (@Sendable @escaping (WorkProgress) -> Void) async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        progress = nil
        let id = UUID()
        operationID = id
        let update: @Sendable (WorkProgress) -> Void = { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.busy, self.operationID == id else { return }
                self.status = update.message
                self.progress = update.fraction.map { min(1, max(0, $0)) }
            }
        }
        Task {
            do { try await operation(update) }
            catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                status = "Couldn't complete this step. You can retry."
            }
            // Invalidate queued progress before the final availability await.
            operationID = UUID()
            await refreshAvailability()
            progress = nil
            busy = false
        }
    }
}
