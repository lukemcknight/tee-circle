import SwiftUI

/// Shown once, between authentication and the app, for any account without a name
/// and handle. TeeCircle 2.0 launched without this, so it also backfills every
/// account created since.
struct ProfileSetupView: View {
    @EnvironmentObject private var store: TeeCircleStore

    @State private var fullName = ""
    @State private var username = ""
    @State private var isSaving = false
    @State private var formError: String?
    @State private var usernameError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case username
    }

    private var canSubmit: Bool {
        !isSaving && PlayerName.isValid(fullName) && Username.isValid(username)
    }

    var body: some View {
        ZStack {
            BroadcastBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    nameField
                    usernameField

                    if let formError {
                        Label(formError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(TeeCircleBrand.signal)
                            .accessibilityIdentifier("profileSetup.error")
                    }

                    saveButton
                }
                .padding(.horizontal, 22)
                .padding(.top, 48)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            // Apple may already have supplied a real name; never make someone
            // retype it.
            if fullName.isEmpty, store.currentDisplayName != "Player" {
                fullName = store.currentDisplayName
            }
            if username.isEmpty, let existing = store.currentUsername {
                username = existing
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TeeCircleMark(size: 46)
            Text("What should we call you?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .tracking(-1)
                .foregroundStyle(TeeCircleBrand.ink)
            Text("Your name shows on the leaderboard. Your username is how friends find you and invite you to rounds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NAME")
            TextField("Jordan Bell", text: $fullName)
                .textContentType(.name)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .username }
                .padding(16)
                .background(TeeCircleBrand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(focusedField == .name ? TeeCircleBrand.signal.opacity(0.5) : TeeCircleBrand.hairline)
                }
                .foregroundStyle(TeeCircleBrand.ink)
                .accessibilityIdentifier("profileSetup.name")
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("USERNAME")
            HStack(spacing: 0) {
                Text("@")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField("jordanbell", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
                    .foregroundStyle(TeeCircleBrand.ink)
                    .accessibilityIdentifier("profileSetup.username")
            }
            .padding(16)
            .background(TeeCircleBrand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focusedField == .username ? TeeCircleBrand.signal.opacity(0.5) : TeeCircleBrand.hairline)
            }
            .onChange(of: username) { _ in
                usernameError = nil
                formError = nil
            }

            if let usernameError {
                Text(usernameError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TeeCircleBrand.signal)
                    .accessibilityIdentifier("profileSetup.usernameError")
            } else {
                Text("3-20 characters. Letters, numbers, underscores, or hyphens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving { ProgressView().tint(TeeCircleBrand.forest) }
                Text(isSaving ? "Saving…" : "Continue")
                    .font(.headline.weight(.black))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(TeeCircleBrand.forest)
            .background(
                canSubmit ? TeeCircleBrand.signal : TeeCircleBrand.raisedCard,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityIdentifier("profileSetup.submit")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.black))
            .tracking(1.1)
            .foregroundStyle(TeeCircleBrand.moss)
    }

    private func save() async {
        guard canSubmit else {
            usernameError = Username.validationMessage(for: username)
            if !PlayerName.isValid(fullName) {
                formError = "Enter the name you want on the leaderboard."
            }
            return
        }
        focusedField = nil
        isSaving = true
        formError = nil
        usernameError = nil

        let outcome = await store.saveProfile(
            fullName: PlayerName.normalize(fullName),
            username: Username.normalize(username)
        )
        isSaving = false

        guard case let .failed(_, message) = outcome else { return }
        if outcome.isUsernameProblem {
            usernameError = message
        } else {
            formError = message
        }
    }
}
