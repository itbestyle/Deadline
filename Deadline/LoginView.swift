import AuthenticationServices
import SwiftUI
import UIKit

struct LoginView: View {
    @ObservedObject var authService = AuthService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var animateLogo = false
    @State private var animateForm = false
    @State private var lastSubmitAt = Date.distantPast
    @State private var isPasswordVisible = false
    @State private var showRegister = false
    @State private var appleSignInCoordinator = AppleSignInCoordinator()
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private static let submitThrottleInterval: TimeInterval = 0.35
    private static let inputSettleAttempts = 4
    private static let inputSettleDelayNs: UInt64 = 80_000_000

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 16)

                VStack(spacing: 10) {
                    Image("LoginIcon")
                        .resizable()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(radius: 12)
                        .padding(.bottom, 4)
                    Text("Redloop")
                        .font(.title.weight(.semibold))
                }
                .opacity(animateLogo ? 1 : 0)
                .scaleEffect(animateLogo ? 1 : 0.96)

                VStack(spacing: 14) {
                    emailField
                    passwordField

                    if shouldShowForgotPassword {
                        forgotPasswordButton
                    }

                    if let error = authService.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if authService.needsEmailVerification {
                        verificationBanner
                    }

                    primaryActionButton
                    googleActionButton
                    appleActionButton
                    registerLinkButton
                }
                .opacity(animateForm ? 1 : 0)
                .offset(y: animateForm ? 0 : 18)
                .padding(.horizontal, 32)

                Spacer(minLength: 28)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animateLogo = true
                }
                withAnimation(.easeOut(duration: 0.45).delay(0.1)) {
                    animateForm = true
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in dismissKeyboard() }
            )
            .onChange(of: password) { _, newValue in
                if newValue.isEmpty {
                    isPasswordVisible = false
                }
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue != .password {
                    isPasswordVisible = false
                }
            }
        }
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(focusedField == .email ? Color.indigo.opacity(0.65) : Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .email)
            .onSubmit {
                withAnimation(.easeInOut(duration: 0.15)) {
                    focusedField = .password
                }
            }
    }

    private var passwordField: some View {
        HStack(spacing: 8) {
            ZStack {
                TextField(L("Пароль"), text: $password)
                    .opacity(isPasswordVisible ? 1 : 0)
                    .allowsHitTesting(isPasswordVisible)
                    .textContentType(.password)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submitFromButtonTap() }

                SecureField(L("Пароль"), text: $password)
                    .opacity(isPasswordVisible ? 0 : 1)
                    .allowsHitTesting(!isPasswordVisible)
                    .textContentType(.password)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submitFromButtonTap() }
            }

            Button {
                isPasswordVisible.toggle()
                if focusedField != .password {
                    focusedField = .password
                }
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(password.isEmpty ? 0 : 1)
            .disabled(password.isEmpty)
            .accessibilityHidden(password.isEmpty)
            .accessibilityLabel(isPasswordVisible ? "Скрыть пароль" : "Показать пароль")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focusedField == .password ? Color.indigo.opacity(0.65) : Color.secondary.opacity(0.35), lineWidth: 1)
        )
    }

    private var primaryActionButton: some View {
        Button {
            submitFromButtonTap()
        } label: {
            if authService.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                Text(L("Войти"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56)
        .foregroundStyle(.white)
        .background(
            Capsule(style: .continuous)
                .fill(isFormValid && !authService.isLoading ? Color.indigo : Color(.tertiarySystemFill))
        )
        .opacity(authService.isLoading ? 0.92 : 1)
        .animation(.easeInOut(duration: 0.2), value: isFormValid)
        .buttonStyle(PremiumPressButtonStyle())
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { submitFromButtonTap() }
        )
        .disabled(authService.isLoading)
    }

    private var verificationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Подтвердите почту"))
                .font(.subheadline.weight(.semibold))

            Text(String(format: L("Мы отправили ссылку на %@. После подтверждения нажмите «Я подтвердил(а)». "), authService.verificationEmail ?? email))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(L("Отправить ещё раз")) {
                    Task {
                        await authService.resendVerification(email: authService.verificationEmail ?? email, password: password)
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var googleActionButton: some View {
        Button {
            Task {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
                await authService.loginWithGoogle()
            }
        } label: {
            HStack(spacing: 9) {
                Image("GoogleLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .offset(y: -0.3)
                Text("Google")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressButtonStyle())
        .disabled(authService.isLoading)
    }

    private var appleActionButton: some View {
        Button {
            appleSignInCoordinator.onLogin = { idToken, nonce in
                Task { await authService.loginWithApple(idToken: idToken, rawNonce: nonce) }
            }
            appleSignInCoordinator.onError = { _ in
                authService.errorMessage = L("Что-то пошло не так. Попробуйте ещё раз.")
                authService.lastAuthErrorKind = .other
            }
            appleSignInCoordinator.start()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Apple")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressButtonStyle())
        .disabled(authService.isLoading)
    }

    private var registerLinkButton: some View {
        Button {
            showRegister = true
        } label: {
            Text(L("Нет аккаунта? Зарегистрироваться"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(TertiaryOpacityButtonStyle())
        .padding(.top, 2)
    }

    private var forgotPasswordButton: some View {
        Button(action: sendPasswordReset) {
            Text(L("Забыли пароль?"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(TertiaryOpacityButtonStyle())
        .disabled(authService.isLoading)
    }

    private var shouldShowForgotPassword: Bool {
        !authService.needsEmailVerification
    }

    private func submitFromButtonTap() {
        guard !authService.isLoading else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSubmitAt) > Self.submitThrottleInterval else { return }
        lastSubmitAt = now

        isPasswordVisible = false
        Task { @MainActor in
            for _ in 0..<Self.inputSettleAttempts {
                if normalizedCredentials != nil { break }
                try? await Task.sleep(nanoseconds: Self.inputSettleDelayNs)
            }
            performLogin()
        }
    }

    private var normalizedCredentials: (email: String, password: String)? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !normalizedPassword.isEmpty else { return nil }
        return (normalizedEmail, normalizedPassword)
    }

    private func performLogin() {
        guard let credentials = normalizedCredentials, !authService.isLoading else { return }

        email = credentials.email
        password = credentials.password

        Task {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
            await authService.login(email: credentials.email, password: credentials.password)

            let resultHaptic = UINotificationFeedbackGenerator()
            if authService.isAuthenticated {
                resultHaptic.notificationOccurred(.success)
            } else if authService.errorMessage != nil {
                resultHaptic.notificationOccurred(.error)
            }
        }
    }

    private func sendPasswordReset() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            authService.errorMessage = L("Введите email, чтобы сбросить пароль")
            authService.lastAuthErrorKind = .invalidInput
            focusedField = .email
            return
        }

        email = normalizedEmail
        dismissKeyboard()

        Task {
            await authService.sendPasswordReset(email: normalizedEmail)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct PremiumPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct TertiaryOpacityButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var pressedOpacity: Double {
        colorScheme == .light ? 0.72 : 0.62
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var onLogin: ((String, String) -> Void)?
    var onError: ((Error?) -> Void)?
    private var currentNonce: String?

    func start() {
        let nonce = AuthService.randomNonceString()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthService.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            onError?(nil)
            return
        }
        onLogin?(idToken, nonce)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onError?(error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let keyWindow = windowScene?.windows.first { $0.isKeyWindow }
        return keyWindow ?? ASPresentationAnchor()
    }
}

#Preview {
    LoginView()
}
