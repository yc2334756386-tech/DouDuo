import ActivityKit

struct DYBrandActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var active: Bool
    }
    let title: String
}
