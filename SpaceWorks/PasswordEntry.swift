import SwiftUI
import UIKit

/// One UIKit text input keeps autofill, selection and keyboard identity while visibility changes.
struct PasswordEntry: UIViewRepresentable {
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var text: String
    var visible = false
    var newPassword = false
    var identifier: String
    var label = String(localized: "Password")
    var focus: Binding<Bool>?
    var onSubmit: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.adjustsFontForContentSizeCategory = true
        field.font = BrandTypography.uiFont(traits: field.traitCollection, boldText: legibilityWeight == .bold)
        field.textColor = UIColor(named: "ink")
        field.tintColor = UIColor(named: "focus")
        field.returnKeyType = .done
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        // A UITextField is a single line. Without an explicit fitting height SwiftUI can
        // allocate all spare tablet height to the representable inside a ScrollView.
        CGSize(width: proposal.width ?? max(1, uiView.intrinsicContentSize.width),
               height: max(48, (uiView.font?.lineHeight ?? 20) + 12))
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let traits = UITraitCollection(traitsFrom: [field.traitCollection,
            UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)])
        field.font = BrandTypography.uiFont(traits: traits, boldText: legibilityWeight == .bold)
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = label
        field.textContentType = newPassword ? .newPassword : .password
        if field.text != text { field.text = text }
        if field.isSecureTextEntry == visible {
            let selection = field.selectedTextRange
            field.isSecureTextEntry = !visible
            // UIKit sometimes resets the caret when switching secure entry; restore it immediately.
            field.selectedTextRange = selection
        }
        if focus?.wrappedValue == true, !field.isFirstResponder {
            DispatchQueue.main.async { [weak field] in
                guard context.coordinator.parent.focus?.wrappedValue == true else { return }
                field?.becomeFirstResponder()
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PasswordEntry
        init(_ parent: PasswordEntry) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.focus?.wrappedValue = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.focus?.wrappedValue = false }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder(); parent.onSubmit(); return true
        }
    }
}

private extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

struct PasswordControl: View {
    let title: String
    @Binding var text: String
    var newPassword = false
    var identifier: String
    var focus: Binding<Bool>?
    @State private var visible = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).brandFont(.headline)
            HStack(spacing: 8) {
                PasswordEntry(text: $text, visible: visible, newPassword: newPassword, identifier: identifier, label: title, focus: focus)
                    .frame(minHeight: 48)
                Button { visible.toggle() } label: {
                    Image(systemName: visible ? "eye.slash" : "eye").frame(width: 48, height: 48)
                }.accessibilityLabel(visible ? "Hide password" : "Show password")
                    .accessibilityValue(visible ? String(localized: "Visible") : String(localized: "Hidden"))
            }.padding(.leading, 12).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
        }
    }
}
