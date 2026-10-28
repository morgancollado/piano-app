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

    @Test func offCenterFoldFillsBothSidesWithSimilarKeys() throws {
        // A side bar on one edge makes the fold sit off the keyboard's centre.
        let fold = FoldInfo(centerX: 400, width: 0)
        let layout = KeyboardLayout(size: CGSize(width: 840, height: 300), fold: fold, targetWhiteKeyWidth: 60)
        let widths = layout.whiteKeys.map(\.frame.width)
        let narrowest = try #require(widths.min())
        let widest = try #require(widths.max())
        #expect((widest - narrowest) / narrowest <= KeyboardLayout.maxSideWidthMismatch + 0.0001)
        // No empty strip at either end.
        #expect(abs((layout.whiteKeys.first?.frame.minX ?? -1) - 0) < 0.001)
        #expect(abs((layout.whiteKeys.last?.frame.maxX ?? -1) - 840) < 0.001)
        // Still a plain gap at the fold.
        let beforeFold = try #require(layout.whiteKeysBeforeFold)
        #expect(FoldAlignment.hasPlainGap(after: layout.whiteKeys[beforeFold - 1].note))
    }

    @Test func screenshotCaseStartsOnCWithNoEmptyStrip() throws {
        // From the first simulator run: the side bar left 630 points left of the fold and 520
        // right of it (pixel-ish numbers, same ratio), which gave B3–B5 and a black strip.
        let fold = FoldInfo(centerX: 630, width: 0)
        let layout = KeyboardLayout(size: CGSize(width: 1150, height: 450), fold: fold, targetWhiteKeyWidth: 74)
        let lowest = try #require(layout.lowestNote)
        #expect([0, 5].contains(lowest.pitchClass), "starts on \(lowest)")
        #expect(abs((layout.whiteKeys.first?.frame.minX ?? -1)) < 0.001)
        #expect(abs((layout.whiteKeys.last?.frame.maxX ?? -1) - 1150) < 0.001)
    }

    // Realistic fold positions: the fold sits near the middle, shifted by a side bar.
    @Test(arguments: [360.0, 420.0, 445.0, 500.0, 560.0])
    func foldLayoutsStartOnCOrFWhenPossible(center: Double) throws {
        let layout = KeyboardLayout(size: CGSize(width: 890, height: 380),
                                    fold: FoldInfo(centerX: center, width: 0), targetWhiteKeyWidth: 60)
        let lowest = try #require(layout.lowestNote)
        #expect([0, 5].contains(lowest.pitchClass), "fold at \(center) starts on \(lowest)")
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
        #expect(layout.startNote(shiftedByOctaves: 1) == nil)
    }

    @Test func keyFramesAreShiftedSideways() throws {
        let layout = KeyboardLayout(size: CGSize(width: 600, height: 200), targetWhiteKeyWidth: 60)
        let frames = layout.keyFrames(shiftedBy: -100)
        #expect(frames.count == layout.whiteKeys.count + layout.blackKeys.count)
        let c4 = try #require(frames[.middleC])
        #expect(c4.minX == -100)
        #expect(c4.width == 60)
    }
}

struct OctaveShiftTests {
    /// 14 white keys at the default width.
    let twoOctaves = CGSize(width: 840, height: 200)

    @Test func shiftsByAnOctaveInTheMiddle() throws {
        let layout = KeyboardLayout(size: twoOctaves, preferredLowestNote: .middleC)
        let up = try #require(layout.startNote(shiftedByOctaves: 1))
        let down = try #require(layout.startNote(shiftedByOctaves: -1))
        #expect(up.name == "C5")
        #expect(down.name == "C3")
    }

    @Test func upIsUnavailableWhenTheShownKeysReachTheTop() {
        // C6 to B7: one more octave would run past C8, so the layout would clamp back to C6.
        let layout = KeyboardLayout(size: twoOctaves, preferredLowestNote: Note(midiNumber: 84))
        #expect(layout.lowestNote?.name == "C6")
        #expect(layout.startNote(shiftedByOctaves: 1) == nil)
        #expect(layout.startNote(shiftedByOctaves: -1)?.name == "C5")
    }

    @Test func usesTheShownRangeNotTheSavedStart() throws {
        // A saved start too high for this many keys is shown an octave lower already.
        let layout = KeyboardLayout(size: twoOctaves, preferredLowestNote: Note(midiNumber: 96))
        #expect(layout.lowestNote?.name == "C6")
        #expect(layout.startNote(shiftedByOctaves: 1) == nil)
        // Octave Down moves what's on screen, rather than only undoing the hidden clamp.
        let down = try #require(layout.startNote(shiftedByOctaves: -1))
        let moved = KeyboardLayout(size: twoOctaves, preferredLowestNote: down)
        #expect(moved.lowestNote?.name == "C5")
    }

    @Test func downIsUnavailableAtTheBottom() {
        let layout = KeyboardLayout(size: twoOctaves, preferredLowestNote: Note(midiNumber: 24))
        #expect(layout.lowestNote?.name == "C1")
        #expect(layout.startNote(shiftedByOctaves: -1) == nil)
    }

    @Test func everyAvailableShiftMovesTheFoldLayout() throws {
        let fold = FoldInfo(centerX: 445, width: 30)
        let size = CGSize(width: 890, height: 380)
        for midi in stride(from: 21, through: 108, by: 1) where Note(midiNumber: midi).isWhite {
            let layout = KeyboardLayout(size: size, fold: fold, preferredLowestNote: Note(midiNumber: midi))
            let lowest = try #require(layout.lowestNote)
            for octaves in [-1, 1] {
                guard let start = layout.startNote(shiftedByOctaves: octaves) else { continue }
                let moved = KeyboardLayout(size: size, fold: fold, preferredLowestNote: start)
                let movedLowest = try #require(moved.lowestNote)
                #expect(octaves > 0 ? movedLowest > lowest : movedLowest < lowest)
                #expect(moved.highestNote.map { Note.pianoRange.contains($0) } == true)
            }
        }
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

    @Test func bookPoseTrailsCoverKeysOnBothPages() throws {
        let division = Division(frame: CGRect(x: 430, y: 0, width: 30, height: 626), isActive: true)
        let surface = PlaySurfaceLayout(size: CGSize(width: 890, height: 626), division: division)
        let trails = try #require(surface.trailsRect)
        #expect(trails.width == 890)
        #expect(trails.maxY == surface.keyboardRect.minY)

        let layout = KeyboardLayout(size: surface.keyboardRect.size, fold: surface.keyboardFold)
        let frames = layout.keyFrames(shiftedBy: surface.keyboardRect.minX - trails.minX)
        let rightmost = try #require(layout.whiteKeys.last)
        let frame = try #require(frames[rightmost.note])
        #expect(frame.minX > division.frame.maxX - 1)
        #expect(frame.midX < trails.width)
    }

    @Test func laptopPoseTrailsMatchTheContentArea() {
        let division = Division(frame: CGRect(x: 0, y: 430, width: 626, height: 30), isActive: true)
        let surface = PlaySurfaceLayout(size: CGSize(width: 626, height: 890), division: division)
        #expect(surface.trailsRect == surface.contentRect)
    }

    @Test func noTrailsWhenThereIsNoRoomAboveTheKeys() {
        let surface = PlaySurfaceLayout(size: CGSize(width: 800, height: 150), division: nil)
        #expect(surface.contentRect == nil)
        #expect(surface.trailsRect == nil)
    }
}
