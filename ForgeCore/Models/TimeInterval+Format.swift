import Foundation

public extension TimeInterval {
    /// "1:23:45" or "23:45" — for per-chapter durations.
    var positional: String {
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "1h 23m" or "23m" — for totals.
    var abbreviated: String {
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
