import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DYBrandActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DYBrandActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image("BrandIcon").resizable().scaledToFit().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 7))
                Text(context.attributes.title).font(.headline).foregroundStyle(.black)
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(.white)
            .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 7) {
                        Image("BrandIcon").resizable().scaledToFit().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(context.attributes.title).font(.headline).foregroundStyle(.black)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white, in: Capsule())
                }
            } compactLeading: {
                Image("BrandIcon").resizable().scaledToFit().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
            } compactTrailing: {
                Text(context.attributes.title).font(.caption.weight(.semibold))
            } minimal: {
                Image("BrandIcon").resizable().scaledToFit().clipShape(Circle())
            }
            .keylineTint(.white)
        }
    }
}
