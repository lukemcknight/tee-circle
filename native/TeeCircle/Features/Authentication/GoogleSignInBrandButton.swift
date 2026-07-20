import SwiftUI

/// Custom Google sign-in button matching the Apple button's geometry
/// (52pt, 14pt continuous radius), per Google's branding guidelines for
/// custom buttons: white surface, official "G" mark, standard label.
struct GoogleSignInBrandButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text("Continue with Google")
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.84))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52, maxHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityIdentifier("auth.google")
    }
}
