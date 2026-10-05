// Compile: swiftc -parse-as-library verify_movie.swift -o /tmp/swiftrender-verify
// Uses only Apple frameworks; no ffmpeg dependency. MIT licensed.
import AVFoundation
import CryptoKit
import Foundation

struct VerificationError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

struct MovieReport: Codable {
    let file: String
    let width: Int
    let height: Int
    let nominalFPS: Double
    let duration: Double
    let decodedFrames: Int
    let audioTracks: Int
    let compressedVideoSHA256: String
    let compressedSamples: Int
    let compressedBytes: Int
    let videoMatchesReference: Bool?
}

struct VideoFingerprint: Equatable {
    let digest: String
    let samples: Int
    let bytes: Int
}

func fingerprint(_ asset: AVAsset, _ track: AVAssetTrack) async throws -> VideoFingerprint {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    guard reader.canAdd(output) else { throw VerificationError("Cannot read compressed video") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? VerificationError("Cannot start video reader") }
    var hash = SHA256()
    var count = 0
    var totalBytes = 0
    let transform = try await track.load(.preferredTransform)
    hash.update(data: Data("\(transform.a),\(transform.b),\(transform.c),\(transform.d),\(transform.tx),\(transform.ty)\n".utf8))
    while let sample = output.copyNextSampleBuffer() {
        let sampleCount = CMSampleBufferGetNumSamples(sample)
        if sampleCount == 0 { continue }
        guard let buffer = CMSampleBufferGetDataBuffer(sample) else {
            throw VerificationError("Compressed video sample has no data")
        }
        let length = CMBlockBufferGetDataLength(buffer)
        guard length > 0 else { throw VerificationError("Compressed sample is empty") }
        var bytes = Data(count: length)
        let status = bytes.withUnsafeMutableBytes { pointer in
            CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { throw VerificationError("Cannot read compressed sample bytes") }
        // Timing is included, so byte-identical frames with changed pacing do not pass.
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let dts = CMSampleBufferGetDecodeTimeStamp(sample)
        let duration = CMSampleBufferGetDuration(sample)
        hash.update(data: Data("\(sampleCount):\(length):\(pts.value)/\(pts.timescale):\(dts.value)/\(dts.timescale):\(duration.value)/\(duration.timescale)\n".utf8))
        hash.update(data: bytes)
        count += sampleCount
        totalBytes += length
    }
    guard reader.status == .completed else { throw reader.error ?? VerificationError("Compressed reader did not complete") }
    return .init(digest: hash.finalize().map { String(format: "%02x", $0) }.joined(), samples: count, bytes: totalBytes)
}

func decode(_ asset: AVAsset, _ track: AVAssetTrack, expectedFPS: Double) throws -> Int {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw VerificationError("Cannot decode video") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? VerificationError("Cannot start decoder") }
    var count = 0
    var previous: Double?
    while let sample = output.copyNextSampleBuffer() {
        if CMSampleBufferGetNumSamples(sample) == 0 { continue }
        guard CMSampleBufferGetImageBuffer(sample) != nil else { throw VerificationError("Decoded frame has no image") }
        let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard seconds.isFinite else { throw VerificationError("Nonfinite video timestamp") }
        if let previous {
            guard seconds > previous, abs(seconds - previous - 1 / expectedFPS) < 0.001 else {
                throw VerificationError("Nonuniform video timestamps at frame \(count)")
            }
        } else if abs(seconds) > 0.001 {
            throw VerificationError("First video frame does not begin at zero")
        }
        previous = seconds
        count += 1
    }
    guard reader.status == .completed else { throw reader.error ?? VerificationError("Decoder did not complete") }
    return count
}

@main
struct VerifyMovie {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Verification failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["--help"] {
            print("Usage: swiftrender-verify MOVIE --width N --height N --fps N --frames N [--audio required|optional|absent] [--compare-video ORIGINAL] [--report FILE]")
            if arguments.isEmpty { throw VerificationError("A movie and expected format are required") }
            return
        }
        let allowed: Set<String> = ["--width", "--height", "--fps", "--frames", "--audio", "--compare-video", "--report"]
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), index + 1 < arguments.count, options[key] == nil else {
                throw VerificationError("Unknown, duplicate, or incomplete option: \(key)")
            }
            options[key] = arguments[index + 1]
            index += 2
        }
        guard let width = Int(options["--width"] ?? ""), width > 0,
              let height = Int(options["--height"] ?? ""), height > 0,
              let fps = Double(options["--fps"] ?? ""), fps.isFinite, fps > 0,
              let frames = Int(options["--frames"] ?? ""), frames > 0 else {
            throw VerificationError("Provide positive --width, --height, --fps, and --frames")
        }
        let audioMode = options["--audio"] ?? "optional"
        guard ["required", "optional", "absent"].contains(audioMode) else { throw VerificationError("Invalid --audio mode") }
        let url = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        guard video.count == 1, let track = video.first else { throw VerificationError("Expected one video track") }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        if audioMode == "required" && audio.isEmpty { throw VerificationError("Required audio track is missing") }
        if audioMode == "absent" && !audio.isEmpty { throw VerificationError("Unexpected audio track") }
        let size = try await track.load(.naturalSize)
        let observedFPS = Double(try await track.load(.nominalFrameRate))
        let duration = try await asset.load(.duration).seconds
        guard Int(size.width.rounded()) == width, Int(size.height.rounded()) == height else {
            throw VerificationError("Dimensions are \(size), expected \(width) × \(height)")
        }
        guard abs(observedFPS - fps) < 0.02 else { throw VerificationError("FPS is \(observedFPS), expected \(fps)") }
        guard duration.isFinite, abs(duration - Double(frames) / fps) <= 1 / fps + 0.001 else {
            throw VerificationError("Movie duration \(duration) does not match expected frames/FPS")
        }
        let decoded = try decode(asset, track, expectedFPS: fps)
        guard decoded == frames else { throw VerificationError("Decoded \(decoded) frames, expected \(frames)") }
        let signature = try await fingerprint(asset, track)
        var matches: Bool?
        if let reference = options["--compare-video"] {
            let referenceAsset = AVURLAsset(url: URL(fileURLWithPath: reference))
            let referenceTracks = try await referenceAsset.loadTracks(withMediaType: .video)
            guard referenceTracks.count == 1, let referenceTrack = referenceTracks.first else {
                throw VerificationError("Reference must have exactly one video track")
            }
            let referenceSignature = try await fingerprint(referenceAsset, referenceTrack)
            matches = signature == referenceSignature
            guard matches == true else { throw VerificationError("Encoded video bytes, timestamps, or transform changed") }
        }
        let report = MovieReport(file: url.path, width: width, height: height, nominalFPS: observedFPS,
                                 duration: duration, decodedFrames: decoded, audioTracks: audio.count,
                                 compressedVideoSHA256: signature.digest, compressedSamples: signature.samples,
                                 compressedBytes: signature.bytes, videoMatchesReference: matches)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        if let destination = options["--report"] {
            let reportURL = URL(fileURLWithPath: destination).standardizedFileURL
            guard reportURL.path != url.path, reportURL.path != options["--compare-video"].map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) else {
                throw VerificationError("Report path must not overwrite a movie")
            }
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: reportURL, options: .atomic)
        }
        print(String(decoding: data, as: UTF8.self))
    }
}
