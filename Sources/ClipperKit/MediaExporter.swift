import AVFoundation
import Foundation

public enum MediaExporter {
    /// Copy while the file picker's security scope is alive; later jobs use only our local copy.
    public static func importRecording(from source: URL, progress: @escaping @Sendable (WorkProgress) -> Void = { _ in }) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { () async throws -> URL in
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let isMKV = ["mkv", "webm"].contains(source.pathExtension.lowercased())
            // Validate before copying large files or publishing a URL to the player.
            let asset = AVURLAsset(url: source)
            // `||` takes a non-async autoclosure, so the playability check can't sit inside it.
            if !isMKV {
                let playable = (try? await asset.load(.isPlayable)) == true
                guard playable else { throw ClipperError.unsupportedMedia }
            }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("Clipper-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(isMKV ? source.deletingPathExtension().lastPathComponent + ".mp4" : source.lastPathComponent)
            do {
                if isMKV {
                    try await MKVConverter.convert(source: source, destination: destination, progress: progress)
                } else {
                    progress(WorkProgress("Copying recording"))
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                return destination
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }.value
    }

    static func audioForTranscription(from source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ClipperError.noAudio
        }
        let trackRange = try await track.load(.timeRange)
        let output = source.deletingLastPathComponent().appendingPathComponent("transcription-\(UUID().uuidString).caf")
        do {
            try await Task.detached(priority: .userInitiated) {
                try decodeToPCM(asset: asset, track: track, leadingSilence: max(0, trackRange.start.seconds), output: output)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }

    /// Voz's 16 kHz mono, as linear PCM. A compressed M4A only estimates its frame count, and on
    /// multi-hour recordings Voz's reads run past the real end and fail ("read failed") near the
    /// finish. PCM's length is exact. Leading silence keeps timestamps aligned with the recording
    /// when the audio track starts after zero.
    private static func decodeToPCM(asset: AVAsset, track: AVAssetTrack, leadingSilence: Double, output: URL) throws {
        let sampleRate = 16_000.0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true) else {
            throw ClipperError.noAudio
        }
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { throw ClipperError.noAudio }
        reader.add(trackOutput)
        let file = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        if leadingSilence > 0 {
            let frames = AVAudioFrameCount(leadingSilence * sampleRate)
            if frames > 0, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) {
                silence.frameLength = frames
                memset(silence.int16ChannelData![0], 0, Int(frames) * MemoryLayout<Int16>.size)
                try file.write(from: silence)
            }
        }
        guard reader.startReading() else { throw reader.error ?? ClipperError.noAudio }
        while let sample = trackOutput.copyNextSampleBuffer() {
            try autoreleasepool {
                let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
                guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                buffer.frameLength = frames
                let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                    sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
                guard status == noErr else { throw ClipperError.noAudio }
                try file.write(from: buffer)
            }
        }
        if reader.status == .failed { throw reader.error ?? ClipperError.noAudio }
        guard file.length > 0 else { throw ClipperError.noAudio }
    }

    /// Export one clip, or a reel by concatenating the supplied clip ranges in order.
    /// Retains the source's framing and orientation. No crop or synthetic timestamps.
    public static func export(source: URL, ranges: [CutRange]) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let bounded = try ClipTiming.bounded(ranges, duration: duration)
        let sourceVideo = try await asset.loadTracks(withMediaType: .video).first
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        guard sourceAudio != nil else { throw ClipperError.noAudio }
        let composition = AVMutableComposition()
        var tracks: [(AVAssetTrack, AVMutableCompositionTrack, CMTimeRange)] = []
        for sourceTrack in [sourceVideo, sourceAudio].compactMap({ $0 }) {
            guard let target = composition.addMutableTrack(withMediaType: sourceTrack.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ClipperError.cannotExport
            }
            if sourceTrack.mediaType == .video {
                target.preferredTransform = try await sourceTrack.load(.preferredTransform)
            }
            tracks.append((sourceTrack, target, try await sourceTrack.load(.timeRange)))
        }
        var cursor = CMTime.zero
        for range in bounded {
            let requested = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600),
                                        end: CMTime(seconds: range.end, preferredTimescale: 600))
            for (sourceTrack, target, available) in tracks {
                let intersection = CMTimeRangeGetIntersection(requested, otherRange: available)
                if intersection.isValid && !intersection.isEmpty {
                    let offset = CMTimeSubtract(intersection.start, requested.start)
                    try target.insertTimeRange(intersection, of: sourceTrack, at: CMTimeAdd(cursor, offset))
                }
            }
            cursor = CMTimeAdd(cursor, requested.duration)
        }
        let hasVideo = sourceVideo != nil
        let output = source.deletingLastPathComponent()
            .appendingPathComponent("highlight-\(UUID().uuidString).\(hasVideo ? "mov" : "m4a")")
        try await export(composition,
                         preset: hasVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A,
                         output: output, fileType: hasVideo ? .mov : .m4a)
        return output
    }

    private static func export(_ asset: AVAsset, preset: String, output: URL, fileType: AVFileType) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ClipperError.cannotExport
        }
        do {
            try await session.export(to: output, as: fileType)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
