import Foundation
// CGRect, CGSize and CGPoint get their Equatable conformance from CoreGraphics on Apple
// platforms, so import it directly. On Linux these types come from Foundation.
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import PianoCore

struct FoldAlignmentTests {
    @Test func twoOctavesFromCKeepC() {
        #expect(FoldAlignment.lowestNote(whiteKeysBeforeFold: 7, near: .middleC) == .middleC)
    }

    @Test(arguments: 1...14)
    func keyBeforeFoldIsAlwaysEOrB(count: Int) throws {
        let lowest = FoldAlignment.lowestNote(whiteKeysBeforeFold: count, near: .middleC)
        let lastBeforeFold = try #require(lowest.whiteKey(offsetBy: count - 1))
        #expect(["E", "B"].contains(String(lastBeforeFold.name.prefix(1))))
        // Never strays more than 3 white keys from the requested start.
        let distance = abs(lowest.midiNumber - Note.middleC.midiNumber)
        #expect(distance <= 5)
    }

    @Test func twelveKeysStartOnD() {
        // C D E F G A | ... would put the fold after A, which has a black key above it.
        // The closest fix is starting on D: D E F G A B | C ...
        let lowest = FoldAlignment.lowestNote(whiteKeysBeforeFold: 6, near: .middleC)
        #expect(lowest.name == "D4")
    }
}

struct KeyboardLayoutTests {
    // iPhone Duo inner display held sideways, assuming 3x scale.
    let innerLandscape = CGSize(width: 890, height: 380)

    @Test func noFoldFillsTheWidth() {
        let layout = KeyboardLayout(size: CGSize(width: 600, height: 200), targetWhiteKeyWidth: 60)
        #expect(layout.whiteKeys.count == 10)
        #expect(layout.whiteKeyWidth == 60)
        #expect(layout.whiteKeys.first?.frame.minX == 0)
        #expect(layout.whiteKeys.last?.frame.maxX == 600)
        #expect(layout.lowestNote == .middleC)
        #expect(layout.whiteKeysBeforeFold == nil)
    }

    @Test func blackKeysFollowThePianoPattern() {
        let layout = KeyboardLayout(size: CGSize(width: 420, height: 200), targetWhiteKeyWidth: 60)
        // C4–B4: five black keys, none after E or B.
        #expect(layout.blackKeys.map(\.note.name) == ["C♯4", "D♯4", "F♯4", "G♯4", "A♯4"])
    }

    @Test func flatDuoGivesTwoOctavesSplitAtBC() throws {
        let fold = FoldInfo(centerX: 445, width: 0)
        let layout = KeyboardLayout(size: innerLandscape, fold: fold, targetWhiteKeyWidth: 60)
        #expect(layout.whiteKeys.count == 14)
        #expect(layout.noteRange?.lowerBound.name == "C4")
        #expect(layout.noteRange?.upperBound.name == "B5")
        #expect(layout.whiteKeysBeforeFold == 7)

        let left = layout.whiteKeys[6]
        let right = layout.whiteKeys[7]
        #expect(left.note.name == "B4")
        #expect(right.note.name == "C5")
        #expect(abs(left.frame.maxX - 445) < 0.001)
        #expect(abs(right.frame.minX - 445) < 0.001)
    }

    @Test func noBlackKeyCrossesTheFold() {
        for center in stride(from: 200.0, through: 690.0, by: 7.0) {
            for foldWidth in [0.0, 24.0] {
                let fold = FoldInfo(centerX: center, width: foldWidth)
                let layout = KeyboardLayout(size: innerLandscape, fold: fold, targetWhiteKeyWidth: 60)
                let clear = (center - foldWidth / 2)...(center + foldWidth / 2)
                for key in layout.blackKeys {
                    #expect(!(key.frame.minX < clear.upperBound && key.frame.maxX > clear.lowerBound),
                            "Black key \(key.note) crosses a fold at \(center)")
                }
            }
        }
    }

    @Test func partlyFoldedLeavesAGapAtTheFold() {
        let fold = FoldInfo(centerX: 445, width: 30)
        let layout = KeyboardLayout(size: innerLandscape, fold: fold, targetWhiteKeyWidth: 60)
        for key in layout.whiteKeys {
            #expect(key.frame.maxX <= 430.0001 || key.frame.minX >= 459.9999)
        }
        #expect(layout.key(at: CGPoint(x: 445, y: 300)) == nil)
    }

    @Test func offCenterFoldKeepsKeysTheSameWidth() {
        // A side bar on one edge makes the fold sit off the keyboard's center.
        let fold = FoldInfo(centerX: 400, width: 0)
        let layout = KeyboardLayout(size: CGSize(width: 840, height: 300), fold: fold, targetWhiteKeyWidth: 60)
        let widths = Set(layout.whiteKeys.map { ($0.frame.width * 1000).rounded() })
        #expect(widths.count == 1)
        #expect(layout.whiteKeys.allSatisfy { $0.frame.minX >= -0.001 && $0.frame.maxX <= 840.001 })
    }

    @Test func foldTooCloseToAnEdgeIsIgnored() {
        let fold = FoldInfo(centerX: 20, width: 0)
        let layout = KeyboardLayout(size: CGSize(width: 600, height: 200), fold: fold, targetWhiteKeyWidth: 60)
        #expect(layout.whiteKeysBeforeFold == nil)
        #expect(layout.whiteKeys.count == 10)
    }

    @Test func hitTestingPrefersBlackKeys() {
        let layout = KeyboardLayout(size: CGSize(width: 420, height: 200), targetWhiteKeyWidth: 60)
        // The C|D boundary is at x = 60. High up it's C♯; lower down it's a white key.
        #expect(layout.key(at: CGPoint(x: 60, y: 50))?.note.name == "C♯4")
        #expect(layout.key(at: CGPoint(x: 55, y: 180))?.note.name == "C4")
        #expect(layout.key(at: CGPoint(x: 65, y: 180))?.note.name == "D4")
        #expect(layout.key(at: CGPoint(x: 65, y: 250)) == nil)
    }

    @Test func rangeStaysOnAnEightyEightKeyPiano() throws {
        let high = KeyboardLayout(size: CGSize(width: 900, height: 200), targetWhiteKeyWidth: 60,
                                  preferredLowestNote: Note(midiNumber: 105))
        let top = try #require(high.highestNote)
        #expect(top <= Note.pianoRange.upperBound)

        let low = KeyboardLayout(size: CGSize(width: 900, height: 200), targetWhiteKeyWidth: 60,
                                 preferredLowestNote: Note(midiNumber: 12))
        let bottom = try #require(low.lowestNote)
        #expect(bottom >= Note.pianoRange.lowerBound)
    }

    @Test func keyWidthIsClampedToTouchableSizes() {
        let layout = KeyboardLayout(size: CGSize(width: 440, height: 200), targetWhiteKeyWidth: 10)
        #expect(layout.whiteKeys.count == 10) // 440 / 44
    }

    @Test func emptySizeGivesNoKeys() {
        let layout = KeyboardLayout(size: .zero)
        #expect(layout.whiteKeys.isEmpty)
        #expect(layout.key(at: .zero) == nil)
    }
}

struct PlaySurfaceLayoutTests {
    @Test func regularIPhoneLandscapePutsKeysAtTheBottom() {
        let surface = PlaySurfaceLayout(size: CGSize(width: 800, height: 360), division: nil)
        #expect(surface.keyboardRect.maxY == 360)
        #expect(surface.keyboardRect.width == 800)
        #expect(surface.contentRect != nil)
        #expect(surface.keyboardFold == nil)
    }

    @Test func laptopPoseSplitsContentAboveKeysBelow() throws {
        let division = Division(frame: CGRect(x: 0, y: 430, width: 626, height: 30), isActive: true)
        let surface = PlaySurfaceLayout(size: CGSize(width: 626, height: 890), division: division)
        let content = try #require(surface.contentRect)
        #expect(content.maxY == 430)
        #expect(surface.keyboardRect.minY == 460)
        #expect(surface.keyboardRect.maxY == 890)
        #expect(surface.keyboardFold == nil)
    }

    @Test func flatDuoPassesTheInactiveFoldToTheKeyboard() throws {
        let division = Division(frame: CGRect(x: 445, y: 0, width: 0, height: 626), isActive: false)
        let surface = PlaySurfaceLayout(size: CGSize(width: 890, height: 626), division: division)
        let fold = try #require(surface.keyboardFold)
        #expect(fold.centerX == 445)
        #expect(fold.width == 0)
        #expect(surface.contentRect?.width == 890)
    }

    @Test func bookPoseKeepsContentOnTheLeftPage() throws {
        let division = Division(frame: CGRect(x: 430, y: 0, width: 30, height: 626), isActive: true)
        let surface = PlaySurfaceLayout(size: CGSize(width: 890, height: 626), division: division)
        let fold = try #require(surface.keyboardFold)
        #expect(fold.width == 30)
        #expect(surface.contentRect?.maxX == 430)
    }
}
