import SwiftUI

/// Editing surface for an account that already completed setup. Same validation
/// and same command as `ProfileSetupView`, but presented as a dismissible sheet
/// rather than a gate.
struct EditIdentityView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var username = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isSaving && PlayerName.isValid(fullName) && Username.isValid(username)
    }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $fullName)
                    .textContentType(.name)
                    .accessibilityIdentifier("identity.name")
            } header: {
                Text("Name")
            } footer: {
                Text("Shown on leaderboards and rosters.")
            }

            Section {
                HStack(spacing: 0) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("identity.username")
                }
            } header: {
                Text("Username")
            } footer: {
                Text(Username.validationMessage(for: username)
                    ?? "3-20 characters. How friends find you.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TeeCircleBrand.signal)
                        .accessibilityIdentifier("identity.error")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BroadcastBackground())
        .navigationTitle("Your identity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("identity.save")
            }
        }
        .onAppear {
            fullName = store.currentDisplayName
            username = store.currentUsername ?? ""
        }
    }

    private func save() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil

        let outcome = await store.saveProfile(
            fullName: PlayerName.normalize(fullName),
            username: Username.normalize(username)
        )
        isSaving = false

        switch outcome {
        case .saved:
            dismiss()
        case let .failed(_, message):
            errorMessage = message
        }
    }
}
