import Foundation
import NaturalLanguage
import Transcript

public struct CutRange: Codable, Sendable, Equatable {
    public let start: Double
    public let end: Double
    public var duration: Double { end - start }

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct ClipResult: Identifiable, Sendable {
    public let id: Int
    public let text: String
    public let score: Double
    public let estimatedDuration: Double
    public let ranges: [CutRange]
    public var playbackDuration: Double? {
        ranges.isEmpty ? nil : ranges.reduce(0) { $0 + $1.duration }
    }

    init(clip: Clip, sentences: [Sentence] = [], duration: Double? = nil) throws {
        id = clip.id
        text = clip.text
        score = clip.score
        estimatedDuration = clip.estimatedDurationSec
        if let duration {
            guard !clip.sentenceIDs.isEmpty,
                  clip.sentenceIDs.allSatisfy({ sentences.indices.contains($0) && sentences[$0].id == $0 }) else {
                throw ClipperError.invalidTimestamps
            }
            ranges = try ClipTiming.bounded(
                clip.ranges(in: sentences).map { CutRange(start: $0.start, end: $0.end) },
                duration: duration
            )
        } else {
            ranges = []
        }
    }
}

public enum TranscriptInput {
    /// Newlines can supply explicit sentence boundaries; paragraphs are tokenized locally.
    public static func sentences(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).flatMap { line in
            let paragraph = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = paragraph
            var sentences: [String] = []
            tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
                let sentence = String(paragraph[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                return true
            }
            return sentences
        }
    }
}

public enum ClipTiming {
    /// SDK padding may run past the media's end. Clamp it, never invent timing from word counts.
    public static func bounded(_ ranges: [CutRange], duration: Double) throws -> [CutRange] {
        guard duration.isFinite, duration > 0, !ranges.isEmpty else {
            throw ClipperError.invalidTimestamps
        }
        return try ranges.map { range in
            guard range.start.isFinite, range.end.isFinite,
                  range.start >= 0, range.end > range.start, range.start < duration else {
                throw ClipperError.invalidTimestamps
            }
            return CutRange(start: range.start, end: min(range.end, duration))
        }
    }
}

public enum ClipperError: LocalizedError {
    case tooFewSentences
    case unsupportedLanguage
    case noAudio
    case invalidTimestamps
    case cannotExport
    case unsupportedMedia
    case conversionFailed

    public var errorDescription: String? {
        switch self {
        case .conversionFailed: "This MKV could not be converted. Check available storage and try another recording. The original file has not been changed."
        case .unsupportedMedia: "Apple's media player cannot open this recording. Convert it to an unprotected MP4 or MOV with H.264/HEVC video and AAC audio, or import an M4A, MP3, or WAV audio file."
        case .tooFewSentences: "Clips needs at least three sentences. Try a longer recording or transcript."
        case .unsupportedLanguage: "This language is not supported by the recording transcriber. Use a transcript instead."
        case .noAudio: "The recording has no readable audio track. Try an unprotected MOV, MP4, M4A, MP3, or WAV file."
        case .invalidTimestamps: "The selected moment has invalid recording timestamps and cannot be exported."
        case .cannotExport: "This media cannot be exported in the selected format. Try a MOV, MP4, M4A, MP3, or WAV file."
        }
    }
}
