import Foundation

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

        var leadingEdges: [CGFloat]
        var keyWidth: CGFloat
        var lowest: Note
        var beforeFold: Int?

        if let fold, let split = Self.split(width: size.width, fold: fold, target: target) {
            keyWidth = split.keyWidth
            beforeFold = split.left
            lowest = FoldAlignment.lowestNote(whiteKeysBeforeFold: split.left, near: preferredLowestNote)
            // Keys hug the fold from both sides; any spare space ends up at the outer edges.
            let foldStart = fold.centerX - fold.width / 2
            let foldEnd = fold.centerX + fold.width / 2
            let width = keyWidth
            let leftCount = split.left
            let leftEdges: [CGFloat] = (0..<leftCount).map { index in
                foldStart - CGFloat(leftCount - index) * width
            }
            let rightEdges: [CGFloat] = (0..<split.right).map { index in
                foldEnd + CGFloat(index) * width
            }
            leadingEdges = leftEdges + rightEdges
        } else {
            let count = max(1, Int((size.width / target).rounded()))
            keyWidth = size.width / CGFloat(count)
            lowest = preferredLowestNote.whiteKey(offsetBy: 0) ?? .middleC
            leadingEdges = (0..<count).map { CGFloat($0) * keyWidth }
        }

        lowest = Self.clampToPiano(lowest, whiteKeyCount: leadingEdges.count)

        var whites: [PianoKey] = []
        whites.reserveCapacity(leadingEdges.count)
        for (index, x) in leadingEdges.enumerated() {
            guard let note = lowest.whiteKey(offsetBy: index) else { break }
            whites.append(PianoKey(note: note, frame: CGRect(x: x, y: 0, width: keyWidth, height: size.height)))
        }

        var blacks: [PianoKey] = []
        let blackWidth = keyWidth * blackKeyWidthRatio
        let blackHeight = size.height * blackKeyHeightRatio
        for index in whites.indices.dropLast() where whites[index].note.hasBlackKeyAbove {
            // Never put a black key across the fold.
            if let beforeFold, index == beforeFold - 1 { continue }
            guard let note = whites[index].note.transposed(by: 1) else { continue }
            let boundary = whites[index].frame.maxX
            blacks.append(PianoKey(
                note: note,
                frame: CGRect(x: boundary - blackWidth / 2, y: 0, width: blackWidth, height: blackHeight)
            ))
        }

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

    static func split(width: CGFloat, fold: FoldInfo, target: CGFloat)
        -> (left: Int, right: Int, keyWidth: CGFloat)?
    {
        let leftSpace = fold.centerX - fold.width / 2
        let rightSpace = width - (fold.centerX + fold.width / 2)
        // Ignore a fold that leaves no room for a usable key on one side.
        let minimum = target * 0.75
        guard leftSpace >= minimum, rightSpace >= minimum else { return nil }
        let left = max(1, Int((leftSpace / target).rounded()))
        let right = max(1, Int((rightSpace / target).rounded()))
        // One width for every key, so both sides look the same.
        let keyWidth = min(leftSpace / CGFloat(left), rightSpace / CGFloat(right))
        return (left, right, keyWidth)
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
