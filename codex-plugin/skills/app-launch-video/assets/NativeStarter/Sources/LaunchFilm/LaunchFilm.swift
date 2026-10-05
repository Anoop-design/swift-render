import AppKit
import AVFoundation
import SwiftUI
import SwiftRender

private struct FilmError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct Options {
    var command: String
    var output = ""
    var width = 1080
    var height = 1920
    var duration = 16.0
    var fps = 30
    var time = 2.0
    var frames = 12
    var audio: String?
    var overwrite = false
    var size: CGSize { CGSize(width: width, height: height) }
    var outputURL: URL { URL(fileURLWithPath: output).standardizedFileURL }

    init(_ arguments: [String]) throws {
        guard let command = arguments.first, ["render", "frame", "contact"].contains(command) else {
            throw FilmError(Self.usage)
        }
        self.command = command
        var cursor = 1
        while cursor < arguments.count {
            let key = arguments[cursor]
            if key == "--overwrite" { overwrite = true; cursor += 1; continue }
            guard cursor + 1 < arguments.count else { throw FilmError("Missing value for \(key)") }
            let value = arguments[cursor + 1]
            switch key {
            case "--output": output = value
            case "--width": width = try Self.integer(value, key)
            case "--height": height = try Self.integer(value, key)
            case "--fps": fps = try Self.integer(value, key)
            case "--frames": frames = try Self.integer(value, key)
            case "--duration": duration = try Self.number(value, key)
            case "--time": time = try Self.number(value, key)
            case "--audio": audio = value
            default: throw FilmError("Unknown option: \(key)\n\(Self.usage)")
            }
            cursor += 2
        }
        if output.isEmpty {
            output = command == "render" ? "out/film.mp4" : "out/\(command).png"
        }
        guard (64...7680).contains(width), (64...7680).contains(height), width % 2 == 0, height % 2 == 0 else {
            throw FilmError("Width and height must be even integers from 64 through 7680.")
        }
        guard (1...120).contains(fps), duration > 0, duration <= 600 else {
            throw FilmError("Use 1–120 fps and a duration greater than zero, up to 600 seconds.")
        }
        let count = duration * Double(fps)
        guard abs(count - count.rounded()) < 0.000001, count >= 1 else {
            throw FilmError("Duration × fps must be a whole number of frames.")
        }
        guard (1...36).contains(frames) else { throw FilmError("Contact --frames must be 1–36.") }
        if command == "frame" && !(time >= 0 && time < duration) {
            throw FilmError("Frame --time must be at least zero and less than duration.")
        }
        let expectedExtension = command == "render" ? "mp4" : "png"
        guard outputURL.pathExtension.lowercased() == expectedExtension else {
            throw FilmError("\(command) output must have a .\(expectedExtension) extension.")
        }
        if !overwrite && FileManager.default.fileExists(atPath: outputURL.path) {
            throw FilmError("Output exists. Choose another path or pass --overwrite: \(outputURL.path)")
        }
        if let audio {
            guard command == "render" else { throw FilmError("--audio applies only to render.") }
            guard URL(fileURLWithPath: audio).standardizedFileURL != outputURL else {
                throw FilmError("Audio source and video output must have different paths.")
            }
        }
    }

    private static func integer(_ value: String, _ option: String) throws -> Int {
        guard let number = Int(value) else { throw FilmError("\(option) needs an integer.") }
        return number
    }
    private static func number(_ value: String, _ option: String) throws -> Double {
        guard let number = Double(value), number.isFinite else { throw FilmError("\(option) needs a finite number.") }
        return number
    }
    static let usage = """
    launch-film render|frame|contact [options]
      --output PATH       MP4 for render, PNG for frame/contact
      --width 1080 --height 1920 --duration 16 --fps 30
      --time 2.0          Timestamp for frame, in seconds
      --frames 12         Number of contact-sheet samples, 1–36
      --audio PATH        Existing full-length soundtrack for render
      --overwrite         Explicitly replace an existing output
    """
}

@main
struct LaunchFilm {
    @MainActor
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] || arguments == ["-h"] { print(Options.usage); return }
            let options = try Options(arguments)
            // Initialize native AppKit services; no simulator or physical device.
            _ = NSApplication.shared
            let recorder = Recorder(config: .init(fps: options.fps, size: options.size, postFX: false))
            switch options.command {
            case "render":
                let audioURL = options.audio.map { URL(fileURLWithPath: $0) }
                if let audioURL { try await validateAudio(audioURL, options: options) }
                try await recorder.render(to: options.outputURL, duration: options.duration, audioURL: audioURL, postFX: false) { time in
                    FilmScene(time: time, duration: options.duration)
                }
                try await verifyMovie(options)
            case "frame":
                try recorder.renderPNG(at: options.time, to: options.outputURL, postFX: false, duration: options.duration) { time in
                    FilmScene(time: time, duration: options.duration)
                }
            case "contact":
                try contactSheet(options)
            default: break
            }
            print("Created \(options.outputURL.path)")
        } catch {
            FileHandle.standardError.write(Data("launch-film: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func validateAudio(_ url: URL, options: Options) async throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw FilmError("Audio is not readable: \(url.path)") }
        let asset = AVURLAsset(url: url)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw FilmError("Audio source contains no audio track.") }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration + 1 / Double(options.fps) >= options.duration else {
            throw FilmError("Soundtrack is shorter than the film. Supply a continuous, full-length mix; the starter does not loop audio.")
        }
    }

    /// Decode every output frame: the upstream recorder may skip an unavailable
    /// ImageRenderer frame, so successful export alone is not enough validation.
    private static func verifyMovie(_ options: Options) async throws {
        let asset = AVURLAsset(url: options.outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else { throw FilmError("Expected one video track.") }
        let size = try await track.load(.naturalSize)
        guard Int(size.width) == options.width, Int(size.height) == options.height else { throw FilmError("Output dimensions do not match the requested canvas.") }
        let duration = try await asset.load(.duration).seconds
        guard abs(duration - options.duration) <= 1 / Double(options.fps) + 0.000001 else { throw FilmError("Output duration differs from the requested duration.") }
        if options.audio != nil {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else { throw FilmError("Requested soundtrack is missing from the exported movie.") }
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? FilmError("Cannot decode output movie.") }
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard abs(time - Double(count) / Double(options.fps)) < 0.0001 else {
                reader.cancelReading()
                throw FilmError("Output contains a missing or mistimed frame near frame \(count).")
            }
            count += 1
        }
        guard reader.status == .completed else { throw reader.error ?? FilmError("Movie decoding failed.") }
        let expected = Int((options.duration * Double(options.fps)).rounded())
        guard count == expected else { throw FilmError("Decoded \(count) frames; expected \(expected).") }
        print("Verified \(count) decoded frames, \(options.width)×\(options.height), \(options.fps) fps.")
    }

    @MainActor
    private static func contactSheet(_ options: Options) throws {
        let columns = min(4, options.frames)
        let tileWidth: CGFloat = 240
        let tileHeight = tileWidth * CGFloat(options.height) / CGFloat(options.width)
        var samples: [(Double, CGImage)] = []
        for index in 0..<options.frames {
            // Use each interval's midpoint; separate frame commands inspect cuts.
            let time = (Double(index) + 0.5) * options.duration / Double(options.frames)
            let frame = RenderFrame(size: options.size, fps: options.fps, duration: options.duration, t: time, postFX: false) {
                FilmScene(time: time, duration: options.duration)
            }
            let renderer = ImageRenderer(content: frame)
            renderer.scale = tileWidth / CGFloat(options.width)
            guard let image = renderer.cgImage else { throw FilmError("Contact sample at \(time)s produced no image.") }
            samples.append((time, image))
        }
        let rows = Int(ceil(Double(samples.count) / Double(columns)))
        let sheet = VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < samples.count {
                            VStack(spacing: 6) {
                                Image(decorative: samples[index].1, scale: 1)
                                    .resizable().frame(width: tileWidth, height: tileHeight)
                                Text(String(format: "%.2f s", samples[index].0))
                                    .font(.system(size: 12)).monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        } else { Color.clear.frame(width: tileWidth, height: tileHeight + 21) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.08))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw FilmError("Cannot encode contact sheet.")
        }
        try FileManager.default.createDirectory(at: options.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: options.outputURL)
    }
}
