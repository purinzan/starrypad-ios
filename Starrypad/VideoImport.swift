import AVFoundation
import PhotosUI
import SwiftUI

/// Pulls the audio out of a video and writes it as a wav.
///
/// The picker is PHPickerViewController, which runs out of process: the app
/// never gets access to the photo library, only to the one item chosen, so
/// there is no library permission to ask for and nothing to explain.
enum VideoImport {

    enum Failure: LocalizedError {
        case noAudioTrack
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "That video has no sound"
            case .unreadable: return "Could not read that video"
            }
        }
    }

    /// The same thing, for a caller that must not return until it is done.
    ///
    /// The picker hands over a file that exists only for the length of its
    /// callback, so the read happens there. Blocking is the point: it is a
    /// background queue, and the alternative is copying a whole film out of
    /// the photo library to keep it alive - gigabytes moved to take five
    /// seconds of a song.
    static func extractAudioBlocking(from url: URL, seconds limit: Double = 30)
    -> Result<String, Error> {
        let done = DispatchSemaphore(value: 0)
        var outcome: Result<String, Error> = .failure(Failure.unreadable)
        Task {
            do { outcome = .success(try await extractAudio(from: url, seconds: limit)) }
            catch { outcome = .failure(error) }
            done.signal()
        }
        done.wait()
        return outcome
    }

    /// Decode the asset's audio to a 48 kHz mono wav in Recordings.
    ///
    /// Long videos are cut at the head rather than refused: a sampler wants a
    /// few seconds, and decoding a whole film to grab a snare is a waste of a
    /// battery. The trim UI then works inside that.
    static func extractAudio(from url: URL, seconds limit: Double = 30) async throws -> String {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw Failure.noAudioTrack
        }
        guard let reader = try? AVAssetReader(asset: asset) else { throw Failure.unreadable }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero,
                                       duration: CMTime(seconds: limit, preferredTimescale: 600))
        guard reader.startReading() else { throw Failure.unreadable }

        var samples = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length,
                                              dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            samples.append(UnsafeBufferPointer(start: pointer, count: length))
        }
        guard reader.status == .completed || reader.status == .reading, !samples.isEmpty else {
            throw Failure.unreadable
        }

        let name = Recordings.newName(prefix: "video")
        try writeWAV(samples, to: Recordings.url(for: name), sampleRate: 48000, channels: 1)
        return name
    }

    /// A 16-bit PCM wav, written by hand because the header is 44 bytes and
    /// pulling in an exporter to produce one would be the larger dependency.
    private static func writeWAV(_ pcm: Data, to url: URL, sampleRate: Int, channels: Int) throws {
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        let byteRate = sampleRate * channels * 2
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                       // PCM chunk size
        append(UInt16(1))                        // format: PCM
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(channels * 2))             // block align
        append(UInt16(16))                       // bits per sample
        header.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        try (header + pcm).write(to: url)
    }
}

/// The system video picker, as something a SwiftUI sheet can present.
struct VideoPicker: UIViewControllerRepresentable {
    /// Called on a background queue with the picked file, which exists only
    /// for as long as this call. Read it here.
    var read: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: VideoPicker
        init(_ parent: VideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                parent.onCancel()
                return
            }
            // The file the picker hands over is cleaned up as soon as this
            // callback returns, so the reading happens inside it. Copying it
            // first is what made importing a long song expensive: the whole
            // video came out of the library twice over to yield a few seconds
            // of audio.
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else {
                    DispatchQueue.main.async { self.parent.onCancel() }
                    return
                }
                self.parent.read(url)
            }
        }
    }
}
