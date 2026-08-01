import SwiftUI
import UIKit

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = AuthService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var localValidationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case confirmPassword
    }

    private static let minimumPasswordLength = 6

    private var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedEmail.isEmpty
            && trimmedPassword.count >= Self.minimumPasswordLength
            && trimmedPassword == trimmedConfirm
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                formSection

                if authService.needsEmailVerification {
                    verificationSection
                }

                if let message = validationOrErrorMessage {
                    errorBanner(message)
                }

                registerButton

                Text(L("После регистрации мы отправим письмо для подтверждения email."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .iPadReadableContent(maxWidth: 520)
        }
        .navigationTitle(L("Регистрация"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("Назад")) { dismiss() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
        .onChange(of: password) { _, newValue in
            if newValue.isEmpty { isPasswordVisible = false }
            localValidationMessage = nil
        }
        .onChange(of: confirmPassword) { _, _ in
            localValidationMessage = nil
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue != .password { isPasswordVisible = false }
            if newValue != .confirmPassword { isConfirmPasswordVisible = false }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated { dismiss() }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Создайте аккаунт"))
                .font(.title2.weight(.bold))
            Text(L("Email и пароль нужны для синхронизации задач между устройствами."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            fieldBlock(title: L("Email")) {
                TextField(L("Email"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }

            fieldBlock(title: L("Пароль")) {
                passwordField(
                    text: $password,
                    isVisible: $isPasswordVisible,
                    field: .password,
                    submitLabel: .next,
                    onSubmit: { focusedField = .confirmPassword }
                )
            }

            fieldBlock(title: L("Повторите пароль")) {
                passwordField(
                    text: $confirmPassword,
                    isVisible: $isConfirmPasswordVisible,
                    field: .confirmPassword,
                    submitLabel: .go,
                    onSubmit: { register() }
                )
            }

            Text(L("Минимум 6 символов"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Подтвердите почту"), systemImage: "envelope.badge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)

            verificationStep(1, String(format: L("Откройте письмо на %@"), authService.verificationEmail ?? email))
            verificationStep(2, L("Нажмите ссылку подтверждения"))
            verificationStep(3, L("Вернитесь сюда и нажмите «Я подтвердил(а)»"))

            HStack(spacing: 12) {
                Button(L("Отправить ещё раз")) {
                    Task {
                        await authService.resendVerification(
                            email: authService.verificationEmail ?? email,
                            password: password
                        )
                    }
                }
                .font(.caption.weight(.semibold))

                Button(L("Я подтвердил(а)")) {
                    Task {
                        await authService.login(email: email, password: password)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
        )
    }

    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )
        }
    }

    private func passwordField(
        text: Binding<String>,
        isVisible: Binding<Bool>,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                TextField(L("Пароль"), text: text)
                    .opacity(isVisible.wrappedValue ? 1 : 0)
                    .allowsHitTesting(isVisible.wrappedValue)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(submitLabel)
                    .focused($focusedField, equals: field)
                    .onSubmit(onSubmit)

                SecureField(L("Пароль"), text: text)
                    .opacity(isVisible.wrappedValue ? 0 : 1)
                    .allowsHitTesting(!isVisible.wrappedValue)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(submitLabel)
                    .focused($focusedField, equals: field)
                    .onSubmit(onSubmit)
            }

            Button {
                isVisible.wrappedValue.toggle()
                focusedField = field
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(text.wrappedValue.isEmpty ? 0 : 1)
            .disabled(text.wrappedValue.isEmpty)
        }
    }

    private func verificationStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.indigo))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var registerButton: some View {
        Button {
            register()
        } label: {
            Group {
                if authService.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(authService.needsEmailVerification ? L("Я подтвердил(а)") : L("Зарегистрироваться"))
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .foregroundStyle(.white)
        .background(
            Capsule(style: .continuous)
                .fill(isFormValid && !authService.isLoading ? Color.indigo : Color(.tertiarySystemFill))
        )
        .disabled(authService.isLoading || (!authService.needsEmailVerification && !isFormValid))
    }

    private var validationOrErrorMessage: String? {
        localValidationMessage ?? authService.errorMessage
    }

    private func register() {
        guard !authService.isLoading else { return }

        if authService.needsEmailVerification {
            Task { await authService.login(email: email, password: password) }
            return
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            localValidationMessage = L("Заполните email и пароль")
            return
        }
        guard trimmedPassword.count >= Self.minimumPasswordLength else {
            localValidationMessage = L("Минимум 6 символов")
            return
        }
        guard trimmedPassword == trimmedConfirm else {
            localValidationMessage = L("Пароли не совпадают")
            return
        }

        email = trimmedEmail
        password = trimmedPassword
        confirmPassword = trimmedConfirm
        localValidationMessage = nil
        dismissKeyboard()

        Task {
            await authService.register(email: trimmedEmail, password: trimmedPassword)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    }
}
