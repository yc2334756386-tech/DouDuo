import ActivityKit
import Foundation

@MainActor
final class DYBrandActivityManager {
    static let shared = DYBrandActivityManager()
    private var activity: Activity<DYBrandActivityAttributes>?

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity, activity.activityState == .active { return }
        let previous = Activity<DYBrandActivityAttributes>.activities
        do {
            activity = try Activity.request(attributes: DYBrandActivityAttributes(title: "抖音"),
                content: ActivityContent(state: .init(active: true), staleDate: nil), pushType: nil)
        } catch { DYLiveModel.log("DDBRAND activity unavailable") }
        Task {
            for item in previous { await item.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func end() async {
        let previous = activity
        activity = nil
        await previous?.end(nil, dismissalPolicy: .immediate)
    }
}
