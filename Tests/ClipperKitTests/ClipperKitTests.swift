import AVFoundation
import Foundation
import Testing
import Transcript
@testable import ClipperKit

@Test func invalidVideoImportReturnsRecoverableError() async throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID()).mp4")
    try Data("not a video".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    do {
        _ = try await MediaExporter.importRecording(from: source)
        Issue.record("Invalid video was accepted")
    } catch ClipperError.unsupportedMedia {
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}

@Test func paragraphBecomesSentences() {
    #expect(TranscriptInput.sentences(from: "One useful idea. Another useful idea! A final question?").count == 3)
}

@Test func newlinesPreserveExplicitBoundaries() {
    #expect(TranscriptInput.sentences(from: "First thought\n\n Second thought \nThird thought") == ["First thought", "Second thought", "Third thought"])
    #expect(TranscriptInput.sentences(from: " \n\t ").isEmpty)
}

@Test func paddingIsClampedToMediaDuration() throws {
    let ranges = try ClipTiming.bounded([CutRange(start: 2, end: 10.15)], duration: 10)
    #expect(ranges == [CutRange(start: 2, end: 10)])
}

@Test func unsafeTimingIsRejected() {
    for range in [CutRange(start: -1, end: 2), CutRange(start: 3, end: 2), CutRange(start: .nan, end: 2), CutRange(start: 1, end: .infinity), CutRange(start: 10, end: 11)] {
        #expect(throws: ClipperError.self) { try ClipTiming.bounded([range], duration: 10) }
    }
    #expect(throws: ClipperError.self) { try ClipTiming.bounded([], duration: 10) }
}

@Test func textOnlyResultsNeverInventCutTimes() throws {
    let result = try ClipResult(clip: fixtureClip(ids: [0, 1]))
    #expect(result.ranges.isEmpty)
    #expect(result.playbackDuration == nil)
    #expect(result.estimatedDuration == 6)
}

@Test func sentenceIDsResolveToRealTimesAndCutPauses() throws {
    let sentences = [
        Sentence(id: 0, text: "First.", start: 1, end: 2),
        Sentence(id: 1, text: "Second.", start: 5, end: 6),
        Sentence(id: 2, text: "Third.", start: 8, end: 10)
    ]
    let result = try ClipResult(clip: fixtureClip(ids: [0, 1]), sentences: sentences, duration: 10)
    #expect(result.ranges.count == 2)
    #expect(result.ranges[0] == CutRange(start: 0.85, end: 2.15))
    #expect(result.ranges[1] == CutRange(start: 4.85, end: 6.15))
}

@Test func missingSentenceCannotSilentlyExportWrongMedia() {
    #expect(throws: ClipperError.self) {
        try ClipResult(clip: fixtureClip(ids: [12]), sentences: [Sentence(id: 0, text: "First.", start: 0, end: 2)], duration: 5)
    }
}

@Test func shortTranscriptFailsBeforeDownloadingModels() async {
    let engine = ClipperEngine()
    await #expect(throws: ClipperError.self) {
        try await engine.select(text: "One sentence.", limit: 5, progress: { _ in })
    }
}

@Test func unsupportedLanguageFailsBeforeReadingMedia() async {
    let engine = ClipperEngine()
    await #expect(throws: ClipperError.self) {
        try await engine.select(recording: URL(fileURLWithPath: "/nonexistent.mov"), language: "unsupported", limit: 5, progress: { _ in })
    }
}

@Test func audioExportCutsAndConcatenatesRealMedia() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipper-test-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.wav")
    let rate = 16_000.0
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64_000))
    buffer.frameLength = 64_000
    let samples = try #require(buffer.floatChannelData?[0])
    for i in 0..<64_000 { samples[i] = Float(sin(Double(i) * 2 * .pi * 440 / rate) * 0.1) }
    // Closing the writer before opening the asset ensures the WAV header is finalized.
    do {
        let file = try AVAudioFile(forWriting: source, settings: format.settings)
        try file.write(from: buffer)
    }
    let extracted = try await MediaExporter.audioForTranscription(from: source)
    let extractedDuration = try await AVURLAsset(url: extracted).load(.duration).seconds
    #expect(abs(extractedDuration - 4) < 0.1)
    let output = try await MediaExporter.export(source: source, ranges: [CutRange(start: 0.5, end: 1), CutRange(start: 2, end: 3)])
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 1.5) < 0.1)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
}

private func fixtureClip(ids: [Int]) -> Clip {
    Clip(id: 0, sentenceIDs: ids, text: "A selected moment.", score: 0.6, percentile: 1, estimatedDurationSec: 6)
}
