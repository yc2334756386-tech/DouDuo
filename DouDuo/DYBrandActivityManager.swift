import ActivityKit
import Foundation

@MainActor
final class DYBrandActivityManager {
    static let shared = DYBrandActivityManager()
    func clearPreviousActivities() async {
        for activity in Activity<DYBrandActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
