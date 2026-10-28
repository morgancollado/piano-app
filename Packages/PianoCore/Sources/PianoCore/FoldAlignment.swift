/// Picks keyboard ranges so the iPhone Duo fold never cuts through a black key.
///
/// No black key sits between E and F or between B and C. If the white key just left
/// of the fold is an E or a B, the fold falls in a plain gap between two white keys.
/// A two-octave keyboard that starts on C has exactly that property: its middle is B|C.
public enum FoldAlignment {
    /// The lowest white key, as close as possible to `preferred`, for which the white key
    /// at position `count` (the last one before the fold) is an E or a B.
    public static func lowestNote(whiteKeysBeforeFold count: Int, near preferred: Note) -> Note {
        precondition(count >= 1, "There must be at least one key before the fold")
        let start = preferred.whiteKey(offsetBy: 0) ?? preferred
        // E and B are never more than 2 white keys from any white key, so ±3 always finds one.
        // Offsets are ordered by distance, preferring the lower range on a tie.
        for offset in [0, -1, 1, -2, 2, -3, 3] {
            guard let candidate = start.whiteKey(offsetBy: offset),
                  let lastBeforeFold = candidate.whiteKey(offsetBy: count - 1),
                  hasPlainGap(after: lastBeforeFold)
            else { continue }
            return candidate
        }
        return start
    }

    /// Whether the boundary just above this white key has no black key on it.
    public static func hasPlainGap(after note: Note) -> Bool {
        note.isWhite && !note.hasBlackKeyAbove
    }
}
