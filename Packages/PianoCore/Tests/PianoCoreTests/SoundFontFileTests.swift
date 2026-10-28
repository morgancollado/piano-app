import Foundation
import Testing
@testable import PianoCore

struct SoundFontFileTests {
    @Test func acceptsASoundFontHeader() {
        var header = Data("RIFF".utf8)
        header.append(contentsOf: [0x2C, 0x26, 0xDA, 0x03])
        header.append(Data("sfbkLIST".utf8))
        #expect(SoundFontFile.problem(withPrefix: header) == nil)
    }

    @Test func spotsAGitLFSPointer() {
        let pointer = Data("""
        version https://git-lfs.github.com/spec/v1
        oid sha256:7f29be413420a927660330f5926e3f7f5c1e6b5df0bb5024539c48a1248c5d12
        size 64693300
        """.utf8)
        #expect(SoundFontFile.problem(withPrefix: pointer) == .gitLFSPointer)
    }

    @Test func rejectsOtherFiles() {
        #expect(SoundFontFile.problem(withPrefix: Data()) == .notASoundFont)
        #expect(SoundFontFile.problem(withPrefix: Data("RIFF\0\0\0\0WAVE".utf8)) == .notASoundFont)
    }
}
