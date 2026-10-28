import Foundation
// CGRect, CGSize and CGPoint get their Equatable conformance from CoreGraphics on Apple
// platforms, so import it directly. On Linux these types come from Foundation.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where a vertical fold crosses the keyboard, in the keyboard's own coordinates.
public struct FoldInfo: Sendable, Equatable {
    /// Horizontal center of the fold.
    public var centerX: CGFloat
    /// Width to keep clear. Zero when the device is flat (the fold is inactive).
    public var width: CGFloat

    public init(centerX: CGFloat, width: CGFloat) {
        self.centerX = centerX
        self.width = max(0, width)
    }
}

public struct PianoKey: Sendable, Equatable, Identifiable {
    public let note: Note
    public let frame: CGRect

    public var id: Int { note.midiNumber }
    public var isBlack: Bool { note.isBlack }

    public init(note: Note, frame: CGRect) {
        self.note = note
        self.frame = frame
    }
}

/// The frame of every key for a given keyboard size, plus hit-testing.
///
/// The number of keys comes from the space available and the preferred key width,
/// never from the device model. When a fold crosses the keyboard, keys on both sides
/// are laid out to meet at the fold, and the range is chosen so an E|F or B|C gap
/// lands on it (see `FoldAlignment`).
public struct KeyboardLayout: Sendable, Equatable {
    public static let defaultWhiteKeyWidth: CGFloat = 60
    /// 44 pt is Apple's minimum comfortable touch target.
    public static let whiteKeyWidthRange: ClosedRange<CGFloat> = 44...90

    public let size: CGSize
    /// Width of the narrowest white key (the two sides of a fold can differ slightly).
    public let whiteKeyWidth: CGFloat
    public let whiteKeys: [PianoKey]
    public let blackKeys: [PianoKey]
    /// How many white keys sit left of the fold, when the layout is split around one.
    public let whiteKeysBeforeFold: Int?

    public var lowestNote: Note? { whiteKeys.first?.note }
    public var highestNote: Note? { whiteKeys.last?.note }
    public var noteRange: ClosedRange<Note>? {
        guard let low = lowestNote, let high = highestNote else { return nil }
        return low...high
    }

    public init(
        size: CGSize,
        fold: FoldInfo? = nil,
        targetWhiteKeyWidth: CGFloat = defaultWhiteKeyWidth,
        preferredLowestNote: Note = .middleC,
        blackKeyWidthRatio: CGFloat = 0.58,
        blackKeyHeightRatio: CGFloat = 0.62
    ) {
        self.size = size
        let target = min(max(targetWhiteKeyWidth, Self.whiteKeyWidthRange.lowerBound),
                         Self.whiteKeyWidthRange.upperBound)

        guard size.width > 0, size.height > 0 else {
            whiteKeyWidth = 0
            whiteKeys = []
            blackKeys = []
            whiteKeysBeforeFold = nil
            return
        }

        // Leading edge and width of every white key, left to right.
        var slots: [(x: CGFloat, width: CGFloat)]
        var lowest: Note
        var beforeFold: Int?

        if let fold, let split = Self.split(width: size.width, fold: fold, target: target,
                                            preferredLowestNote: preferredLowestNote) {
            beforeFold = split.left
            lowest = split.lowest
            // Keys meet at the fold from both sides. Each side may have a slightly different key
            // width (at most `maxSideWidthMismatch`) so both sides fill their space exactly.
            let foldStart = fold.centerX - fold.width / 2
            let foldEnd = fold.centerX + fold.width / 2
            let leftWidth = split.leftWidth
            let rightWidth = split.rightWidth
            let leftCount = split.left
            let leftSlots: [(x: CGFloat, width: CGFloat)] = (0..<leftCount).map { index in
                (x: foldStart - CGFloat(leftCount - index) * leftWidth, width: leftWidth)
            }
            let rightSlots: [(x: CGFloat, width: CGFloat)] = (0..<split.right).map { index in
                (x: foldEnd + CGFloat(index) * rightWidth, width: rightWidth)
            }
            slots = leftSlots + rightSlots
        } else {
            let count = max(1, Int((size.width / target).rounded()))
            let width = size.width / CGFloat(count)
            lowest = preferredLowestNote.whiteKey(offsetBy: 0) ?? .middleC
            slots = (0..<count).map { (x: CGFloat($0) * width, width: width) }
        }

        lowest = Self.clampToPiano(lowest, whiteKeyCount: slots.count)

        var whites: [PianoKey] = []
        whites.reserveCapacity(slots.count)
        for (index, slot) in slots.enumerated() {
            guard let note = lowest.whiteKey(offsetBy: index) else { break }
            whites.append(PianoKey(note: note, frame: CGRect(x: slot.x, y: 0, width: slot.width, height: size.height)))
        }

        var blacks: [PianoKey] = []
        let blackHeight = size.height * blackKeyHeightRatio
        for index in whites.indices.dropLast() where whites[index].note.hasBlackKeyAbove {
            // Never put a black key across the fold.
            if let beforeFold, index == beforeFold - 1 { continue }
            guard let note = whites[index].note.transposed(by: 1) else { continue }
            let blackWidth = whites[index].frame.width * blackKeyWidthRatio
            let boundary = whites[index].frame.maxX
            blacks.append(PianoKey(
                note: note,
                frame: CGRect(x: boundary - blackWidth / 2, y: 0, width: blackWidth, height: blackHeight)
            ))
        }

        let keyWidth = whites.map(\.frame.width).min() ?? 0
        whiteKeyWidth = keyWidth
        whiteKeys = whites
        blackKeys = blacks
        whiteKeysBeforeFold = beforeFold
    }

    /// The key under a point. Black keys win where they overlap white keys.
    public func key(at point: CGPoint) -> PianoKey? {
        guard point.y >= 0, point.y <= size.height else { return nil }
        if let black = blackKeys.first(where: { $0.frame.contains(point) }) {
            return black
        }
        return whiteKeys.first { point.x >= $0.frame.minX && point.x < $0.frame.maxX }
    }

    public func key(for note: Note) -> PianoKey? {
        (note.isBlack ? blackKeys : whiteKeys).first { $0.note == note }
    }

    /// How far down the key a point is: 0 at the top edge, 1 at the bottom edge.
    public func depth(of point: CGPoint, in key: PianoKey) -> CGFloat {
        guard key.frame.height > 0 else { return 0 }
        return min(max((point.y - key.frame.minY) / key.frame.height, 0), 1)
    }

    // MARK: - Helpers

    /// Largest allowed difference in key width between the two sides of the fold (10%).
    /// The crease separates the halves, so a small difference isn't noticeable, while equal
    /// widths would leave an empty strip at one end whenever the fold is off-centre.
    static let maxSideWidthMismatch: CGFloat = 0.10

    struct Split {
        var left: Int
        var right: Int
        var leftWidth: CGFloat
        var rightWidth: CGFloat
        var lowest: Note
    }

    /// How many keys go on each side of the fold, and how wide they are.
    ///
    /// Tries key counts around the target width on both sides and picks the best by:
    /// keys close to the target width, similar widths on both sides, and a range that starts
    /// on C or F (a keyboard that starts on B looks wrong). Returns nil if the fold leaves no
    /// room for a usable key on one side.
    static func split(width: CGFloat, fold: FoldInfo, target: CGFloat, preferredLowestNote: Note) -> Split? {
        let leftSpace = fold.centerX - fold.width / 2
        let rightSpace = width - (fold.centerX + fold.width / 2)
        let minimum = target * 0.75
        guard leftSpace >= minimum, rightSpace >= minimum else { return nil }

        let baseLeft = max(1, Int((leftSpace / target).rounded()))
        let baseRight = max(1, Int((rightSpace / target).rounded()))
        let narrowest = whiteKeyWidthRange.lowerBound * 0.9

        var best: (cost: CGFloat, split: Split)?
        for left in max(1, baseLeft - 1)...(baseLeft + 1) {
            for right in max(1, baseRight - 1)...(baseRight + 1) {
                let leftWidth = leftSpace / CGFloat(left)
                let rightWidth = rightSpace / CGFloat(right)
                let narrower = min(leftWidth, rightWidth)
                let mismatch = abs(leftWidth - rightWidth) / narrower
                guard mismatch <= maxSideWidthMismatch, narrower >= narrowest else { continue }

                let lowest = FoldAlignment.lowestNote(whiteKeysBeforeFold: left, near: preferredLowestNote)
                let startsWell = lowest.pitchClass == 0 || lowest.pitchClass == 5
                let average = (leftWidth + rightWidth) / 2
                let cost = 4 * abs(log(average / target)) + 5 * mismatch + (startsWell ? 0 : 1)
                if best == nil || cost < best!.cost {
                    best = (cost, Split(left: left, right: right, leftWidth: leftWidth,
                                        rightWidth: rightWidth, lowest: lowest))
                }
            }
        }
        if let best { return best.split }

        // Nothing fits within the allowed mismatch: use one width and leave spare space at the
        // outer edge of the roomier side.
        let keyWidth = min(leftSpace / CGFloat(baseLeft), rightSpace / CGFloat(baseRight))
        let lowest = FoldAlignment.lowestNote(whiteKeysBeforeFold: baseLeft, near: preferredLowestNote)
        return Split(left: baseLeft, right: baseRight, leftWidth: keyWidth, rightWidth: keyWidth, lowest: lowest)
    }

    /// Moves the range by whole octaves until it fits on an 88-key piano.
    /// Moving by octaves keeps the fold alignment intact.
    static func clampToPiano(_ note: Note, whiteKeyCount: Int) -> Note {
        let range = Note.pianoRange
        var lowest = note
        func top(_ start: Note) -> Note? { start.whiteKey(offsetBy: whiteKeyCount - 1) }

        while (top(lowest).map { $0 > range.upperBound } ?? true),
              let lower = lowest.transposed(by: -12), lower >= range.lowerBound {
            lowest = lower
        }
        while lowest < range.lowerBound, let higher = lowest.transposed(by: 12),
              (top(higher).map { $0 <= range.upperBound } ?? false) {
            lowest = higher
        }
        return lowest
    }
}
