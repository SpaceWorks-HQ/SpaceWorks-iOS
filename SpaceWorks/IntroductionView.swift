import SwiftUI

struct IntroductionView: View {
    let finish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private let headings = ["Make room.", "Borrow with confidence.", "One place for your making."]
    private let details = ["Find tools, book a space, and see what's next at your makerspace.",
                           "Request what you need and keep an eye on your loans and due dates.",
                           "Keep bookings, event tickets, payments, and updates together."]
    private let symbols = [["wrench.and.screwdriver", "shippingbox", "hammer"],
                           ["list.clipboard", "calendar", "checkmark.seal"],
                           ["calendar", "ticket", "tray"]]
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Brand remains outside the animated content tree at every page transition.
                    BrandWordmark()
                    HStack {
                        Text("\(page + 1) of 3").foregroundStyle(Color.swMuted).accessibilityLabel("Introduction, page \(page + 1) of 3")
                        Spacer()
                        Button("Skip introduction", action: finish).frame(minHeight: 48)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        if geometry.size.height >= 650 && !typeSize.isAccessibilitySize {
                            HStack(spacing: 16) {
                                ForEach(symbols[page], id: \.self) { symbol in
                                    Image(systemName: symbol).font(.system(size: 32)).frame(maxWidth: .infinity, minHeight: 100)
                                        .background(Color.swPanel, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.swLine))
                                }
                            }.padding(20).background(Color.swSuccessSoft, in: RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
                        }
                        Text(headings[page]).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(details[page]).font(.title3).foregroundStyle(Color.swMuted)
                    }.id(page).transition(.opacity)
                    Spacer(minLength: 16)
                    Button(page == 2 ? "Get started" : "Next") {
                        if page == 2 { finish() }
                        else { withAnimation(reduceMotion ? nil : MobileMotion.expandAnimation) { page += 1 } }
                    }.buttonStyle(SWPrimary()).accessibilityIdentifier("intro-next")
                    Button("Back") { withAnimation(reduceMotion ? nil : MobileMotion.expandAnimation) { page -= 1 } }
                        .frame(minHeight: 48).opacity(page == 0 ? 0 : 1)
                        .disabled(page == 0).accessibilityHidden(page == 0)
                }.padding(24).frame(maxWidth: 600).frame(minHeight: geometry.size.height, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
            }.background(Color.swBg)
        }
    }
}
