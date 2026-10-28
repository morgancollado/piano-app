import Foundation

/// A quick check of a SoundFont before it's handed to the system sampler, whose loader can
/// abort the app on a file it can't read instead of returning an error.
public enum SoundFontFile {
    public enum Problem: Sendable, Equatable {
        /// The file is a Git LFS pointer: the clone was made without Git LFS installed.
        case gitLFSPointer
        /// The file doesn't start like a SoundFont 2 file (`RIFF` … `sfbk`).
        case notASoundFont
    }

    /// How many bytes from the start of the file `problem(withPrefix:)` needs.
    public static let prefixLength = 32

    /// What's wrong with a file that starts with `prefix`, or nil if it looks like a SoundFont.
    public static func problem(withPrefix prefix: Data) -> Problem? {
        let bytes = [UInt8](prefix.prefix(prefixLength))
        if bytes.starts(with: Array("version https://git-lfs".utf8)) {
            return .gitLFSPointer
        }
        guard bytes.count >= 12,
              bytes[0..<4].elementsEqual("RIFF".utf8),
              bytes[8..<12].elementsEqual("sfbk".utf8)
        else { return .notASoundFont }
        return nil
    }
}
