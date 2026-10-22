import AVFoundation
import AudioToolbox
import Foundation

/// A file's audio format: what it's encoded with and its quality, for the Lossless Only
/// filter and for choosing which copy of a duplicated song to keep.
nonisolated struct AudioFormat: Sendable, Equatable, Hashable {
    enum Codec: String, Sendable, CaseIterable {
        case flac, alac, pcm, aac, mp3, opus, other

        var isLossless: Bool { self == .flac || self == .alac || self == .pcm }

        /// Short name for labels ("FLAC", "ALAC", "WAV/AIFF", "AAC", "MP3").
        var displayName: String {
            switch self {
            case .flac: "FLAC"
            case .alac: "ALAC"
            case .pcm: "Uncompressed"
            case .aac: "AAC"
            case .mp3: "MP3"
            case .opus: "Opus"
            case .other: "Other"
            }
        }
    }

    var codec: Codec
    /// Hz (0 when unknown).
    var sampleRate: Double
    /// Bits per sample (lossless files only).
    var bitDepth: Int?
    /// Average kbps.
    var bitRate: Int?

    var isLossless: Bool { codec.isLossless }

    /// Extensions that are always lossless (".m4a" can be ALAC or AAC, so it isn't here).
    static let losslessExtensions: Set<String> = ["flac", "wav", "aif", "aiff", "caf", "alac"]

    /// "FLAC · 24-bit/96 kHz", "MP3 · 320 kbps".
    var label: String {
        if isLossless {
            let khz = sampleRate > 0 ? (sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1))) + " kHz" : nil
            let detail = [bitDepth.map { "\($0)-bit" }, khz].compactMap { $0 }.joined(separator: "/")
            return detail.isEmpty ? codec.displayName : "\(codec.displayName) · \(detail)"
        }
        return bitRate.map { "\(codec.displayName) · \($0) kbps" } ?? codec.displayName
    }

    /// The codec from a Core Audio format ID.
    static func codec(for formatID: AudioFormatID) -> Codec {
        switch formatID {
        case kAudioFormatFLAC: .flac
        case kAudioFormatAppleLossless: .alac
        case kAudioFormatLinearPCM: .pcm
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD: .aac
        case kAudioFormatMPEGLayer3: .mp3
        case kAudioFormatOpus: .opus
        default: .other
        }
    }

    /// Bits per sample from a stream description: PCM keeps it in `mBitsPerChannel`;
    /// FLAC and ALAC encode the source bit depth in `mFormatFlags`.
    static func bitDepth(of description: AudioStreamBasicDescription, codec: Codec) -> Int? {
        switch codec {
        case .pcm:
            return description.mBitsPerChannel > 0 ? Int(description.mBitsPerChannel) : nil
        case .flac, .alac:
            switch description.mFormatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData: return 16
            case kAppleLosslessFormatFlag_20BitSourceData: return 20
            case kAppleLosslessFormatFlag_24BitSourceData: return 24
            case kAppleLosslessFormatFlag_32BitSourceData: return 32
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Reads a file's format from its header (fast: no decoding). `nil` if it can't be opened.
    static func read(url: URL) -> AudioFormat? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let description = file.fileFormat.streamDescription.pointee
        let codec = codec(for: description.mFormatID)
        let seconds = file.processingFormat.sampleRate > 0 ? Double(file.length) / file.processingFormat.sampleRate : 0
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let kbps = seconds > 0 && bytes > 0 ? Int((Double(bytes) * 8 / seconds / 1000).rounded()) : nil
        return AudioFormat(codec: codec, sampleRate: description.mSampleRate,
                           bitDepth: bitDepth(of: description, codec: codec), bitRate: kbps)
    }
}
