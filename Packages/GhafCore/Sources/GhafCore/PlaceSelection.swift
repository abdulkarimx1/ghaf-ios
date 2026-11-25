import Foundation

/// Conservative automatic POI selection for a manual transaction.
public enum PlaceSelection {
    /// A shop is selected only when the nearest candidate is within 30 m and every
    /// alternative is more than 60 m away. Otherwise no shop can be inferred safely.
    public static func selectedCandidateIndex(distances: [Double]) -> Int? {
        let sorted = distances.enumerated().sorted { $0.element < $1.element }
        guard let first = sorted.first, first.element >= 0, first.element <= 30 else { return nil }
        guard sorted.count == 1 || sorted[1].element > 60 else { return nil }
        return first.offset
    }

    /// An area (neighbourhood) name tolerates an indoor fix; 50 m dropped most indoor saves (row 29).
    public static func acceptsAreaAccuracy(_ accuracy: Double) -> Bool {
        accuracy.isFinite && accuracy >= 0 && accuracy <= 100
    }

    /// Inferring a shop needs a tighter fix than an area.
    public static func acceptsShopAccuracy(_ accuracy: Double) -> Bool {
        accuracy.isFinite && accuracy >= 0 && accuracy <= 50
    }

    /// The phone's live position only describes a purchase dated within 30 minutes of now;
    /// an entry dated yesterday, or opened later, must not get today's position.
    public static func isLiveLocationValid(for purchaseDate: Date, now: Date = .now) -> Bool {
        abs(now.timeIntervalSince(purchaseDate)) <= 30 * 60
    }
}
