import SwiftUI
import GoogleSignIn
import AuthenticationServices

/// Official controls with an injected action. A demo action never requests a provider credential.
struct GoogleProviderButton: UIViewRepresentable {
    let wide: Bool
    let action: () -> Void
    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.colorScheme = .light
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonPressed), for: .touchUpInside)
        return button
    }
    func updateUIView(_ view: GIDSignInButton, context: Context) {
        context.coordinator.action = action
        view.style = wide ? .wide : .standard
        view.accessibilityLabel = String(localized: "Sign in with Google")
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func buttonPressed() { action() }
    }
}

struct AppleProviderButton: UIViewRepresentable {
    let action: () -> Void
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .whiteOutline)
        button.cornerRadius = 10
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonPressed), for: .touchUpInside)
        return button
    }
    func updateUIView(_ view: ASAuthorizationAppleIDButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func buttonPressed() { action() }
    }
}
