import AuthenticationServices
import GoogleSignInSwift
import SwiftUI
import UIKit

struct AuthenticationView: View {
    private enum FocusedField: Hashable {
        case email
        case password
        case otp
    }

    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: FocusedField?
    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 42

    @State private var email = ""
    @State private var password = ""
    @State private var usePassword = false
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var showsEmailForm = false
    @State private var isSubmitting = false
    @State private var inlineError: String?
    @State private var appleNonce: AppleSignInNonce?

    var body: some View {
        ZStack {
            authenticationBackground

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        authenticationCard
                            .id("auth.card")

                        if store.configuration.useMockData {
                            fixtureButton
                        }

                        legalLinks
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: showsEmailForm) { isShowing in
                    guard isShowing else { return }
                    if reduceMotion {
                        proxy.scrollTo("auth.card", anchor: .center)
                    } else {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            proxy.scrollTo("auth.card", anchor: .center)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var authenticationBackground: some View {
        BroadcastBackground()
            .overlay {
            LinearGradient(
                colors: [TeeCircleBrand.night.opacity(0.08), TeeCircleBrand.night.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            }
            .overlay {
            RadialGradient(
                colors: [TeeCircleBrand.signal.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 430
            )
            }
            .overlay {
            VStack {
                Spacer()
                HStack(spacing: 11) {
                    ForEach(0..<8, id: \.self) { index in
                        Capsule()
                            .fill(index == 3 ? TeeCircleBrand.signal.opacity(0.18) : Color.white.opacity(0.025))
                            .frame(width: 2, height: CGFloat(20 + index * 7))
                    }
                }
                .rotationEffect(.degrees(64))
                .offset(x: -155, y: 25)
            }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 11) {
                TeeCircleMark(size: min(markSize, 54))

                VStack(alignment: .leading, spacing: 2) {
                    Text("TEE CIRCLE")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .tracking(1.6)
                    Text("YOUR ROUND STARTS HERE")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.35)
                        .foregroundStyle(TeeCircleBrand.moss)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("TeeCircle")
            .accessibilityIdentifier("auth.wordmark")

            Text("Make the tee time.\nThe group will follow.")
                .font(.system(size: 39, weight: .black, design: .rounded))
                .tracking(-1.5)
                .lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)

            Text("Create a round in under a minute, send it to the chat, and know who’s in before you get to the first tee.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                authProof("clock.fill", "Fast setup")
                authProof("message.fill", "Easy invites")
                authProof("checkmark.circle.fill", "Clear RSVPs")
            }
        }
        .foregroundStyle(.white)
    }

    private func authProof(_ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.76))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.055), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.075)) }
    }

    private var authenticationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Get on the card")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TeeCircleBrand.ink)

                Text("Sign in once. Your rounds and invite links stay with you.")
                    .font(.subheadline)
                    .foregroundStyle(TeeCircleBrand.ink.opacity(0.62))
            }

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    appleNonce = store.prepareAppleRequest(request)
                } onCompletion: { result in
                    finishAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(minHeight: 52, maxHeight: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.apple")

                if googleIsConfigured {
                    GoogleSignInButton(
                        scheme: .light,
                        style: .wide,
                        state: isSubmitting ? .disabled : .normal,
                        action: beginGoogleSignIn
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.16))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("auth.google")
                }
            }

            emailDivider

            if showsEmailForm {
                emailForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button(action: showEmailForm) {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(TeeCircleBrand.signal)
                        Text("Continue with email")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TeeCircleBrand.ink.opacity(0.48))
                    }
                    .foregroundStyle(TeeCircleBrand.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(TeeCircleBrand.hairline)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.email.toggle")
            }
        }
        .padding(20)
        .background(TeeCircleBrand.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(TeeCircleBrand.signal.opacity(0.16))
        }
        .shadow(color: Color.black.opacity(0.38), radius: 28, y: 16)
    }

    private var emailDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(TeeCircleBrand.ink.opacity(0.12))
                .frame(height: 1)
                .accessibilityHidden(true)

            Text("OR USE EMAIL")
                .font(.caption2.weight(.black))
                .tracking(1.25)
                .foregroundStyle(TeeCircleBrand.ink.opacity(0.56))
                .fixedSize()

            Rectangle()
                .fill(TeeCircleBrand.ink.opacity(0.12))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EMAIL SIGN-IN")
                    .font(.caption.weight(.black))
                    .tracking(1.15)
                    .foregroundStyle(TeeCircleBrand.signal)

                Spacer()

                Button("Hide") { hideEmailForm() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TeeCircleBrand.signal)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("auth.email.hide")
            }

            emailModeControl

            if otpSent && !usePassword {
                otpRecipient
            } else {
                LabeledAuthField(title: "Email address", systemImage: "envelope.fill") {
                    TextField(
                        "",
                        text: $email,
                        prompt: Text("you@example.com")
                            .foregroundColor(TeeCircleBrand.ink.opacity(0.42))
                    )
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(usePassword ? .next : .go)
                    .onSubmit {
                        if usePassword {
                            focusedField = .password
                        } else {
                            submitEmail()
                        }
                    }
                    .onChange(of: email) { _ in inlineError = nil }
                    .accessibilityIdentifier("auth.email")
                }
            }

            if usePassword {
                LabeledAuthField(title: "Password", systemImage: "lock.fill") {
                    SecureField(
                        "",
                        text: $password,
                        prompt: Text("Your password")
                            .foregroundColor(TeeCircleBrand.ink.opacity(0.42))
                    )
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submitEmail)
                    .onChange(of: password) { _ in inlineError = nil }
                    .accessibilityIdentifier("auth.password")
                }
            } else if otpSent {
                LabeledAuthField(title: "Six-digit code", systemImage: "number.circle.fill") {
                    TextField(
                        "",
                        text: $otpCode,
                        prompt: Text("000000")
                            .foregroundColor(TeeCircleBrand.ink.opacity(0.42))
                    )
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .otp)
                    .onChange(of: otpCode) { value in
                        let normalized = String(value.filter { $0.isNumber }.prefix(6))
                        if normalized != value { otpCode = normalized }
                        inlineError = nil
                    }
                    .accessibilityIdentifier("auth.otp")
                }
            }

            if let inlineError {
                Label(inlineError, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("auth.inlineError")
            }

            Button(action: submitEmail) {
                HStack(spacing: 9) {
                    if isSubmitting {
                        ProgressView()
                            .tint(TeeCircleBrand.forest)
                            .accessibilityIdentifier("auth.progress")
                    }
                    Text(emailButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .foregroundStyle(TeeCircleBrand.forest)
                .background(TeeCircleBrand.signal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.72 : 1)
            .accessibilityIdentifier("auth.submit")
        }
    }

    private var emailModeControl: some View {
        HStack(spacing: 4) {
            emailModeButton(
                title: "Email code",
                selected: !usePassword,
                identifier: "auth.mode.code"
            ) {
                setEmailMode(password: false)
            }

            emailModeButton(
                title: "Password",
                selected: usePassword,
                identifier: "auth.mode.password"
            ) {
                setEmailMode(password: true)
            }
        }
        .padding(4)
        .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Email sign-in method")
    }

    private func emailModeButton(
        title: String,
        selected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(selected ? TeeCircleBrand.ink : TeeCircleBrand.ink.opacity(0.58))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(
                    selected ? TeeCircleBrand.pine : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .shadow(color: selected ? Color.black.opacity(0.2) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var otpRecipient: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(TeeCircleBrand.signal)

            VStack(alignment: .leading, spacing: 2) {
                Text("Code sent to")
                    .font(.caption)
                    .foregroundStyle(TeeCircleBrand.ink.opacity(0.58))
                Text(normalizedEmail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TeeCircleBrand.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button("Change") { changeOTPEmail() }
                .font(.footnote.weight(.bold))
                .foregroundStyle(TeeCircleBrand.signal)
                .disabled(isSubmitting)
        }
        .padding(13)
        .background(TeeCircleBrand.signal.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var fixtureButton: some View {
        Button {
            store.enterPreview()
        } label: {
            Label("Open a demo round", systemImage: "sparkles")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.09), in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.14)) }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the local native prototype without a network account")
        .accessibilityIdentifier("auth.fixtureClubhouse")
    }

    private var legalLinks: some View {
        VStack(spacing: 5) {
            Text("By continuing, you agree to TeeCircle’s")

            HStack(spacing: 6) {
                Link(destination: store.configuration.webBaseURL.appending(path: "terms")) {
                    Text("Terms").underline()
                }
                    .accessibilityIdentifier("auth.terms")
                Text("and")
                Link(destination: store.configuration.webBaseURL.appending(path: "privacy")) {
                    Text("Privacy Policy").underline()
                }
                    .accessibilityIdentifier("auth.privacy")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.68))
        .tint(.white.opacity(0.9))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var googleIsConfigured: Bool {
        !store.configuration.googleIOSClientID.isEmpty
            && !store.configuration.googleServerClientID.isEmpty
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailButtonTitle: String {
        if isSubmitting { return "Working…" }
        if usePassword { return "Sign in with password" }
        return otpSent ? "Verify code" : "Send sign-in code"
    }

    private func showEmailForm() {
        inlineError = nil
        if reduceMotion {
            showsEmailForm = true
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                showsEmailForm = true
            }
        }
    }

    private func hideEmailForm() {
        focusedField = nil
        inlineError = nil
        if reduceMotion {
            showsEmailForm = false
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                showsEmailForm = false
            }
        }
    }

    private func setEmailMode(password: Bool) {
        guard usePassword != password else { return }
        focusedField = nil
        inlineError = nil
        otpSent = false
        otpCode = ""
        if reduceMotion {
            usePassword = password
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                usePassword = password
            }
        }
    }

    private func changeOTPEmail() {
        otpSent = false
        otpCode = ""
        inlineError = nil
        focusedField = .email
    }

    private func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        if store.configuration.useMockData {
            store.enterPreview()
            return
        }

        guard !isSubmitting else { return }
        focusedField = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            await store.finishAppleSignIn(result: result, nonce: appleNonce)
        }
    }

    private func beginGoogleSignIn() {
        if store.configuration.useMockData {
            store.enterPreview()
            return
        }

        guard !isSubmitting else { return }
        guard let presenter = UIApplication.shared.teeCircleTopViewController else {
            store.errorMessage = "Google Sign-In could not open. Please try again."
            return
        }

        focusedField = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            await store.signInWithGoogle(presenting: presenter)
        }
    }

    private func submitEmail() {
        if store.configuration.useMockData {
            store.enterPreview()
            return
        }

        guard !isSubmitting else { return }
        guard validateEmailForm() else { return }

        focusedField = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            if usePassword {
                await store.signIn(email: normalizedEmail, password: password)
            } else if otpSent {
                await store.verifyEmailOTP(email: normalizedEmail, code: otpCode)
            } else {
                let didSend = await store.sendEmailOTP(to: normalizedEmail)
                if didSend {
                    otpSent = true
                    otpCode = ""
                    focusedField = .otp
                }
            }
        }
    }

    private func validateEmailForm() -> Bool {
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              !normalizedEmail.contains(where: { $0.isWhitespace })
        else {
            inlineError = "Enter a valid email address."
            focusedField = .email
            return false
        }

        if usePassword && password.isEmpty {
            inlineError = "Enter your password."
            focusedField = .password
            return false
        }

        if !usePassword && otpSent && otpCode.count != 6 {
            inlineError = "Enter the six-digit code from your email."
            focusedField = .otp
            return false
        }

        inlineError = nil
        return true
    }
}

private struct LabeledAuthField<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(TeeCircleBrand.ink.opacity(0.68))

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(TeeCircleBrand.signal)
                    .accessibilityHidden(true)

                content
                    .font(.body)
                    .foregroundStyle(TeeCircleBrand.ink)
                    .tint(TeeCircleBrand.signal)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TeeCircleBrand.ink.opacity(0.13))
            }
        }
    }
}

private extension UIApplication {
    var teeCircleTopViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var current = root
        while let presented = current?.presentedViewController { current = presented }
        return current
    }
}
