import Foundation
import AVFAudio

struct FLACDetails {
    let sampleRate: Int
    let bitsPerSample: Int
    let channels: Int
    let totalSamples: UInt64
    let title: String?
    let artist: String?
    let album: String?
    let albumArtist: String?
    let artwork: Data?

    var duration: TimeInterval {
        sampleRate > 0 ? Double(totalSamples) / Double(sampleRate) : 0
    }
}

enum FLACError: LocalizedError {
    case unsupportedFile
    case decoderError
    case invalidFormat
    case seekFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "无法解码该 FLAC：请确认文件完整，且为 16/24-bit 单声道或立体声。"
        case .decoderError: return "FLAC 解码失败或音频数据损坏。"
        case .invalidFormat: return "无法创建 PCM 播放格式。"
        case .seekFailed: return "无法跳转到所选播放位置。"
        }
    }
}

/// This instance MUST only be accessed from a single serial queue.
final class FLACDecoder {
    private let handle: OpaquePointer
    let details: FLACDetails
    let format: AVAudioFormat

    init(url: URL) throws {
        guard let h = flac_bridge_open(url.path) else { throw FLACError.unsupportedFile }
        handle = h
        let rate = Int(flac_bridge_sample_rate(h))
        let bits = Int(flac_bridge_bits_per_sample(h))
        let channels = Int(flac_bridge_channels(h))
        guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: Double(rate),
                                    channels: AVAudioChannelCount(channels),
                                    interleaved: false) else {
            flac_bridge_close(h)
            throw FLACError.invalidFormat
        }
        format = f

        func tag(_ pointer: UnsafePointer<CChar>?) -> String? {
            guard let pointer else { return nil }
            let value = String(cString: pointer).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        var artLength: Int = 0
        let artworkPointer = flac_bridge_picture(h, &artLength)
        let artwork: Data? = (artLength > 0 && artworkPointer != nil)
            ? Data(bytes: artworkPointer!, count: artLength) : nil
        details = FLACDetails(sampleRate: rate,
                              bitsPerSample: bits,
                              channels: channels,
                              totalSamples: flac_bridge_total_samples(h),
                              title: tag(flac_bridge_title(h)),
                              artist: tag(flac_bridge_artist(h)),
                              album: tag(flac_bridge_album(h)),
                              albumArtist: tag(flac_bridge_album_artist(h)),
                              artwork: artwork)
    }

    deinit { flac_bridge_close(handle) }

    /// Converts interleaved Float32 returned by libFLAC to non-interleaved PCM.
    /// No EQ, normalization or gain processing is applied.
    func readBuffer(frames capacity: AVAudioFrameCount = 16_384) throws -> AVAudioPCMBuffer? {
        let channels = details.channels
        var interleaved = [Float](repeating: 0, count: Int(capacity) * channels)
        let n = interleaved.withUnsafeMutableBufferPointer {
            flac_bridge_read(handle, $0.baseAddress, capacity)
        }
        if n < 0 { throw FLACError.decoderError }
        if n == 0 { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
              let channelData = buffer.floatChannelData else { throw FLACError.invalidFormat }
        buffer.frameLength = AVAudioFrameCount(n)
        for frame in 0..<Int(n) {
            for channel in 0..<channels {
                channelData[channel][frame] = interleaved[frame * channels + channel]
            }
        }
        return buffer
    }

    func seek(sample: UInt64) throws {
        guard flac_bridge_seek(handle, sample) != 0 else { throw FLACError.seekFailed }
    }
}
