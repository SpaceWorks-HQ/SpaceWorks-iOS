import SwiftUI

struct MobileLinkNotice: View {
    let router: MobileLinkRouter
    var body: some View {
        if router.busy {
            ProgressView("Opening your update…").frame(maxWidth: .infinity, minHeight: 48).background(Color.swPanel)
        } else if let error = router.error {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Color.swDanger)
                    .accessibilityIdentifier("mobile-link-error")
                HStack {
                    if router.hasPending {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button("Retry opening update") { Task { await router.process() } }.frame(minHeight: 48)
                                .disabled((router.retryAfter ?? .distantPast) > context.date)
                        }
                    }
                    Button("Dismiss") { router.cancelIntent() }.frame(minHeight: 48)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.swPanel)
        }
    }
}
