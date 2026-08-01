import SwiftData
import SwiftUI

private func AS(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @ObservedObject private var auth = AuthService.shared

    @State private var showDeleteConfirmation = false
    @State private var showPasswordPrompt = false
    @State private var deletePassword = ""
    @State private var deletionError: String?
    @State private var didDeleteAccount = false

    var body: some View {
        List {
            Section {
                if let email = auth.currentEmail {
                    LabeledContent(AS("Email"), value: email)
                } else {
                    Text(AS("Аккаунт активен"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(AS("Профиль"))
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text(AS("Удалить аккаунт"))
                        Spacer()
                        if auth.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(auth.isLoading)
                .accessibilityIdentifier("deleteAccountButton")
            } footer: {
                Text(AS("Аккаунт и все связанные задачи будут безвозвратно удалены с сервера и с этого устройства. Это действие нельзя отменить."))
                    .font(.caption)
            }

            if let deletionError {
                Section {
                    Text(deletionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(AS("Аккаунт"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AS("Готово")) { dismiss() }
            }
        }
        .alert(AS("Удалить аккаунт?"), isPresented: $showDeleteConfirmation) {
            Button(AS("Отмена"), role: .cancel) {}
            Button(AS("Удалить навсегда"), role: .destructive) {
                showPasswordPrompt = true
            }
        } message: {
            Text(AS("Все ваши задачи и данные аккаунта будут удалены. Подписки управляются через App Store и не отменяются автоматически."))
        }
        .sheet(isPresented: $showPasswordPrompt) {
            deleteConfirmationSheet
                .iPadFormSheetPresentation()
        }
        .onChange(of: didDeleteAccount) { _, deleted in
            if deleted { dismiss() }
        }
    }

    private var deleteConfirmationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text(AS("Подтвердите удаление аккаунта. Если вы входили по email, введите пароль."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField(AS("Пароль (если вход по email)"), text: $deletePassword)
                        .textContentType(.password)
                        .accessibilityIdentifier("deleteAccountPasswordField")
                } header: {
                    Text(AS("Пароль"))
                } footer: {
                    Text(AS("Для входа через Apple или Google пароль не нужен."))
                }

                if let deletionError {
                    Section {
                        Text(deletionError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(AS("Подтверждение"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AS("Отмена")) {
                        deletePassword = ""
                        deletionError = nil
                        showPasswordPrompt = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AS("Удалить"), role: .destructive) {
                        Task { await performAccountDeletion() }
                    }
                    .disabled(auth.isLoading)
                    .accessibilityIdentifier("confirmDeleteAccountButton")
                }
            }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func performAccountDeletion() async {
        deletionError = nil
        let password = deletePassword.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await auth.deleteAccount(password: password.isEmpty ? nil : password)
            wipeLocalData()
            deletePassword = ""
            showPasswordPrompt = false
            didDeleteAccount = true
        } catch AuthService.AccountDeletionError.needsRecentLogin {
            deletionError = AS("Введите текущий пароль и попробуйте снова.")
        } catch {
            deletionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func wipeLocalData() {
        do {
            let models = try modelContext.fetch(FetchDescriptor<DeadlineModel>())
            for model in models {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            // Best-effort local wipe after server deletion.
        }

        WidgetAppGroupStore.saveCritical(nil)
        NotificationManager.shared.rescheduleAll(for: [])
        LiveActivityManager.endAll()
    }
}
