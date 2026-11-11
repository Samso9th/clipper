import AVFoundation
import Foundation
import ffmpegkit

/// Embedded FFmpeg runs on both Mac and iPhone; no shell or external installation.
enum MKVConverter {
    static func convert(source: URL, destination: URL,
                        progress: @escaping @Sendable (WorkProgress) -> Void) async throws {
        progress(WorkProgress("Inspecting MKV recording"))
        let codecs = await Task.detached(priority: .userInitiated) { probeStreams(source) }.value
        guard let codecs else { throw ClipperError.unsupportedMedia }
        guard let audio = codecs.first(where: { $0.0 == "audio" }) else { throw ClipperError.noAudio }
        var video = codecs.first(where: { $0.0 == "video" })
        let canCopyVideo = video == nil || ["h264", "hevc"].contains(video!.1)
        if let codec = video?.1, !canCopyVideo {
            progress(WorkProgress("Checking the video can be decoded on this Mac"))
            // This FFmpeg build has no software AV1 decoder, and M1/M2 have no AV1 hardware decode,
            // so YouTube's AV1 downloads fail on those Macs. A full transcode would spin on errors for
            // the whole file before failing; a two-second trial decode finds out up front.
            let decodes = await Task.detached(priority: .userInitiated) { canDecodeVideo(source) }.value
            if !decodes {
                progress(WorkProgress("This Mac can't decode \(codec.uppercased()) video. Importing the audio only"))
                video = nil
            }
        }
        var attempts: [(String, [String])] = []
        if video == nil {
            attempts.append(audio.1 == "aac"
                ? ("Repackaging the audio without quality loss", ["-vn", "-c:a", "copy"])
                : ("Converting the audio on this device", ["-vn", "-c:a", "aac", "-b:a", "192k"]))
        } else {
            if canCopyVideo && audio.1 == "aac" {
                attempts.append(("Repackaging MKV without quality loss", ["-c", "copy"]))
            }
            if canCopyVideo {
                attempts.append(("Converting audio; preserving original video", ["-c:v", "copy", "-c:a", "aac", "-b:a", "192k"]))
            }
            attempts.append(("Converting MKV video and audio on this device", [
                "-c:v", "h264_videotoolbox", "-b:v", "8M", "-pix_fmt", "yuv420p",
                "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:a", "aac", "-b:a", "192k"
            ]))
        }
        let videoMap = video == nil ? [] : ["-map", "0:v:0"]
        for (message, encoding) in attempts {
            progress(WorkProgress(message))
            try? FileManager.default.removeItem(at: destination)
            var arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                             "-protocol_whitelist", "file,pipe", "-i", source.path]
                + videoMap + ["-map", "0:a:0", "-sn", "-dn"] + encoding
            if video?.1 == "hevc" && encoding.contains("copy") { arguments += ["-tag:v", "hvc1"] }
            arguments += ["-avoid_negative_ts", "make_zero", "-movflags", "+faststart", destination.path]
            let command = arguments
            let succeeded = await Task.detached(priority: .userInitiated) {
                ReturnCode.isSuccess(FFmpegKit.executeWithArguments(command).getReturnCode())
            }.value
            if succeeded, (try? await AVURLAsset(url: destination).load(.isPlayable)) == true {
                progress(WorkProgress("MKV conversion complete", fraction: 1))
                return
            }
        }
        throw ClipperError.conversionFailed
    }

    /// Decodes the first two seconds of video and discards them.
    static func canDecodeVideo(_ source: URL) -> Bool {
        let session = FFmpegKit.executeWithArguments([
            "-hide_banner", "-loglevel", "error", "-nostdin", "-xerror", "-t", "2",
            "-i", source.path, "-map", "0:v:0", "-f", "null", "-"
        ])
        return ReturnCode.isSuccess(session.getReturnCode())
    }

    /// (codec_type, codec_name) per stream. ffmpeg-kit's session output interleaves its own
    /// debug log lines with ffprobe's JSON, so `getMediaInformation()` fails to parse and
    /// returns nil for every file. Have ffprobe write the JSON to a file instead.
    static func probeStreams(_ source: URL) -> [(String, String)]? {
        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipper-probe-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: report) }
        let session = FFprobeKit.executeWithArguments([
            "-v", "error", "-print_format", "json", "-show_streams", "-o", report.path, source.path
        ])
        guard ReturnCode.isSuccess(session.getReturnCode()),
              let data = try? Data(contentsOf: report),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else { return nil }
        return streams.map { ($0["codec_type"] as? String ?? "", $0["codec_name"] as? String ?? "") }
    }
}
