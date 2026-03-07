import Foundation
import Combine
import WidgetKit
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

class AuthService: ObservableObject {
    enum AuthErrorKind {
        case invalidCredentials
        case invalidInput
        case network
        case unverifiedEmail
        case other
    }

    static let shared = AuthService()
    
    @Published var isAuthenticated = false
    @Published var currentEmail: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastAuthErrorKind: AuthErrorKind?
    @Published var needsEmailVerification = false
    @Published var verificationEmail: String?
    
    private let baseURL = "https://deadlines-api-bpptyv4q3a-ew.a.run.app"
    private let tokenKey = "auth_token"
    private let emailKey = "user_email"
    private let appGroup = "group.tic-tac-toe.Deadline"
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }
    
    var token: String? {
        sharedDefaults?.string(forKey: tokenKey)
    }
    
    private init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            isAuthenticated = true
            currentEmail = "ui-testing@local"
            return
        }

        // Check if we have a stored token
        if let storedToken = sharedDefaults?.string(forKey: tokenKey),
           !storedToken.isEmpty {
            isAuthenticated = true
            currentEmail = sharedDefaults?.string(forKey: emailKey)
        }
    }
    
    @MainActor
    func register(email: String, password: String) async {
        #if canImport(FirebaseAuth)
        isLoading = true
        errorMessage = nil
        lastAuthErrorKind = nil
        needsEmailVerification = false

        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            try await authResult.user.sendEmailVerification()
            verificationEmail = email
            needsEmailVerification = true
            isAuthenticated = false
            currentEmail = nil
            errorMessage = localized("Письмо подтверждения отправлено. Проверьте почту.")
            try? Auth.auth().signOut()
        } catch {
            errorMessage = firebaseReadableError(error)
            lastAuthErrorKind = firebaseErrorKind(error)
        }

        isLoading = false
        #else
        await performLegacyAuth(endpoint: "/auth/register", email: email, password: password)
        #endif
    }
    
    @MainActor
    func login(email: String, password: String) async {
        #if canImport(FirebaseAuth)
        isLoading = true
        errorMessage = nil
        lastAuthErrorKind = nil
        needsEmailVerification = false

        do {
            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            let user = authResult.user

            guard user.isEmailVerified else {
                verificationEmail = email
                needsEmailVerification = true
                isAuthenticated = false
                currentEmail = nil
                errorMessage = localized("Почта не подтверждена. Проверьте email.")
                lastAuthErrorKind = .unverifiedEmail
                try? Auth.auth().signOut()
                isLoading = false
                return
            }

            let idToken = try await user.getIDToken()
            let apiResponse = try await exchangeFirebaseToken(idToken)
            applyAuthSuccess(token: apiResponse.token, email: apiResponse.email)
        } catch {
            errorMessage = firebaseReadableError(error)
            lastAuthErrorKind = firebaseErrorKind(error)
            isAuthenticated = false
        }

        isLoading = false
        #else
        await performLegacyAuth(endpoint: "/auth/login", email: email, password: password)
        #endif
    }

    @MainActor
    func loginWithGoogle() async {
        #if canImport(FirebaseAuth)
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        lastAuthErrorKind = nil
        needsEmailVerification = false

        do {
            let provider = OAuthProvider(providerID: AuthProviderID.google.rawValue)
            provider.scopes = ["email", "profile"]

            let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthCredential, Error>) in
                provider.getCredentialWith(nil) { credential, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let credential else {
                        continuation.resume(throwing: NSError(domain: "AuthService", code: -2, userInfo: [NSLocalizedDescriptionKey: self.localized("Не удалось получить Google credential")]))
                        return
                    }
                    continuation.resume(returning: credential)
                }
            }

            let authResult = try await Auth.auth().signIn(with: credential)

            let firebaseIDToken = try await authResult.user.getIDToken()
            let apiResponse = try await exchangeFirebaseToken(firebaseIDToken)
            applyAuthSuccess(token: apiResponse.token, email: apiResponse.email)
        } catch {
            errorMessage = firebaseReadableError(error)
            lastAuthErrorKind = firebaseErrorKind(error)
            isAuthenticated = false
        }
        #else
        errorMessage = localized("FirebaseAuth SDK не подключён")
        #endif
    }

    @MainActor
    func loginWithApple(idToken: String, rawNonce: String) async {
        #if canImport(FirebaseAuth)
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        lastAuthErrorKind = nil
        needsEmailVerification = false

        do {
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: nil)
            let authResult = try await Auth.auth().signIn(with: credential)
            let firebaseIDToken = try await authResult.user.getIDToken()
            let apiResponse = try await exchangeFirebaseToken(firebaseIDToken)
            applyAuthSuccess(token: apiResponse.token, email: apiResponse.email)
        } catch {
            errorMessage = firebaseReadableError(error)
            lastAuthErrorKind = firebaseErrorKind(error)
            isAuthenticated = false
        }
        #else
        errorMessage = localized("FirebaseAuth SDK не подключён")
        #endif
    }
    
    @MainActor
    private func performLegacyAuth(endpoint: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        lastAuthErrorKind = nil
        needsEmailVerification = false
        
        guard let url = URL(string: baseURL + endpoint) else {
            errorMessage = localized("Invalid URL")
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email, "password": password]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = localized("Invalid response")
                isLoading = false
                return
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let token = json["token"] as? String {
                        // Save token and email to shared UserDefaults
                        sharedDefaults?.set(token, forKey: tokenKey)
                        sharedDefaults?.set(email, forKey: emailKey)
                        
                        // Refresh widget
                        WidgetCenter.shared.reloadAllTimelines()
                        
                        isAuthenticated = true
                        currentEmail = email
                        verificationEmail = nil
                        needsEmailVerification = false
                    } else if (json["requires_verification"] as? Bool) == true {
                        let apiEmail = (json["email"] as? String) ?? email
                        verificationEmail = apiEmail
                        needsEmailVerification = true
                        isAuthenticated = false
                        currentEmail = nil
                        errorMessage = (json["message"] as? String) ?? localized("Подтвердите почту, затем войдите")
                        lastAuthErrorKind = .unverifiedEmail
                    }
                }
            } else {
                if httpResponse.statusCode == 403 {
                    verificationEmail = email
                    needsEmailVerification = true
                    if endpoint == "/auth/login" {
                        lastAuthErrorKind = .unverifiedEmail
                    }
                }

                // Try to parse error message - first as JSON, then as plain text
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let parsedMessage: String
                    if let error = json["error"] as? String {
                        errorMessage = error
                        parsedMessage = error
                    } else if let message = json["message"] as? String {
                        errorMessage = message
                        parsedMessage = message
                    } else {
                        errorMessage = localizedStatusError(httpResponse.statusCode)
                        parsedMessage = errorMessage ?? ""
                    }

                    if endpoint == "/auth/login" {
                        lastAuthErrorKind = classifyLegacyLoginError(statusCode: httpResponse.statusCode, message: parsedMessage)
                    }

                    if (json["requires_verification"] as? Bool) == true {
                        verificationEmail = (json["email"] as? String) ?? email
                        needsEmailVerification = true
                        if endpoint == "/auth/login" {
                            lastAuthErrorKind = .unverifiedEmail
                        }
                    }
                } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    errorMessage = text
                    if endpoint == "/auth/login" {
                        lastAuthErrorKind = classifyLegacyLoginError(statusCode: httpResponse.statusCode, message: text)
                    }
                    if text.localizedCaseInsensitiveContains("подтверж") ||
                        text.localizedCaseInsensitiveContains("verif") {
                        verificationEmail = email
                        needsEmailVerification = true
                        if endpoint == "/auth/login" {
                            lastAuthErrorKind = .unverifiedEmail
                        }
                    }
                } else {
                    errorMessage = localizedStatusError(httpResponse.statusCode)
                    if endpoint == "/auth/login" {
                        lastAuthErrorKind = classifyLegacyLoginError(statusCode: httpResponse.statusCode, message: errorMessage ?? "")
                    }
                }
            }
        } catch {
            errorMessage = userFacingTransportError(error)
            if endpoint == "/auth/login" {
                lastAuthErrorKind = .network
            }
        }
        
        isLoading = false
    }
    
    @MainActor
    func resendVerification(email: String, password: String? = nil) async {
        #if canImport(FirebaseAuth)
        isLoading = true
        defer { isLoading = false }
        lastAuthErrorKind = nil

        do {
            if let currentUser = Auth.auth().currentUser,
               currentUser.email?.lowercased() == email.lowercased() {
                try await currentUser.sendEmailVerification()
                errorMessage = localized("Письмо отправлено. Проверьте почту.")
                return
            }

            guard let password, !password.isEmpty else {
                errorMessage = localized("Введите пароль, чтобы повторно отправить письмо")
                return
            }

            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            try await authResult.user.sendEmailVerification()
            verificationEmail = email
            needsEmailVerification = true
            errorMessage = localized("Письмо отправлено. Проверьте почту.")
            try? Auth.auth().signOut()
        } catch {
            errorMessage = firebaseReadableError(error)
            lastAuthErrorKind = firebaseErrorKind(error)
        }
        #else
        isLoading = true
        defer { isLoading = false }
        lastAuthErrorKind = nil

        guard let url = URL(string: baseURL + "/auth/resend-verification") else {
            errorMessage = localized("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                errorMessage = localized("Invalid response")
                return
            }

            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = localized("Письмо отправлено. Проверьте почту.")
                }
            } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                errorMessage = text
            } else {
                errorMessage = localizedStatusError(http.statusCode)
            }
        } catch {
            errorMessage = userFacingTransportError(error)
            lastAuthErrorKind = .network
        }
        #endif
    }

    @MainActor
    func sendPasswordReset(email: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            errorMessage = localized("Введите email для сброса пароля")
            lastAuthErrorKind = .invalidInput
            return
        }

        #if canImport(FirebaseAuth)
        isLoading = true
        defer { isLoading = false }
        lastAuthErrorKind = nil

        do {
            try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
            errorMessage = localized("Письмо для сброса пароля отправлено. Проверьте почту.")
        } catch {
            errorMessage = firebaseReadableError(error)
            lastAuthErrorKind = firebaseErrorKind(error)
        }
        #else
        isLoading = true
        defer { isLoading = false }
        lastAuthErrorKind = nil

        guard let url = URL(string: baseURL + "/auth/forgot-password") else {
            errorMessage = localized("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": normalizedEmail])
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                errorMessage = localized("Invalid response")
                return
            }

            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = localized("Письмо для сброса пароля отправлено. Проверьте почту.")
                }
            } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                errorMessage = text
            } else {
                errorMessage = localizedStatusError(http.statusCode)
            }
        } catch {
            errorMessage = userFacingTransportError(error)
            lastAuthErrorKind = .network
        }
        #endif
    }

    @MainActor
    func logout() {
        #if canImport(FirebaseAuth)
        try? Auth.auth().signOut()
        #endif
        sharedDefaults?.removeObject(forKey: tokenKey)
        sharedDefaults?.removeObject(forKey: emailKey)
        
        // Refresh widget
        WidgetCenter.shared.reloadAllTimelines()
        
        isAuthenticated = false
        currentEmail = nil
        needsEmailVerification = false
        verificationEmail = nil
        lastAuthErrorKind = nil
    }

    // MARK: - Firebase backend exchange
    private struct FirebaseLoginResponse: Decodable {
        let token: String?
        let email: String?
        let requiresVerification: Bool?
        let message: String?
    }

    private func exchangeFirebaseToken(_ idToken: String) async throws -> (token: String, email: String) {
        guard let url = URL(string: baseURL + "/auth/firebase/login") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": idToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 200 {
            let decoded = try JSONDecoder().decode(FirebaseLoginResponse.self, from: data)
            guard let token = decoded.token, let email = decoded.email else {
                throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: localized("Некорректный ответ сервера")])
            }
            return (token, email)
        }

        if let decoded = try? JSONDecoder().decode(FirebaseLoginResponse.self, from: data),
           (decoded.requiresVerification ?? false) {
            let email = decoded.email ?? verificationEmail
            if let email { verificationEmail = email }
            needsEmailVerification = true
            throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: decoded.message ?? localized("Почта не подтверждена")])
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }

        throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: localizedStatusError(http.statusCode)])
    }

    private func applyAuthSuccess(token: String, email: String) {
        sharedDefaults?.set(token, forKey: tokenKey)
        sharedDefaults?.set(email, forKey: emailKey)
        WidgetCenter.shared.reloadAllTimelines()
        isAuthenticated = true
        currentEmail = email
        verificationEmail = nil
        needsEmailVerification = false
        errorMessage = nil
        lastAuthErrorKind = nil
    }

    private func classifyLegacyLoginError(statusCode: Int, message: String) -> AuthErrorKind {
        let lowered = message.lowercased()
        if lowered.contains("подтверж") || lowered.contains("verif") {
            return .unverifiedEmail
        }
        if statusCode == 401 || lowered.contains("невер") || lowered.contains("invalid credential") || lowered.contains("wrong password") || lowered.contains("user not found") {
            return .invalidCredentials
        }
        if lowered.contains("network") || lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("сеть") {
            return .network
        }
        return .other
    }

    private func firebaseErrorKind(_ error: Error) -> AuthErrorKind {
        #if canImport(FirebaseAuth)
        if let authError = error as NSError?, authError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: authError.code) {
            switch code {
            case .wrongPassword, .invalidCredential, .userNotFound:
                return .invalidCredentials
            case .invalidEmail, .weakPassword:
                return .invalidInput
            case .networkError:
                return .network
            default:
                return .other
            }
        }
        #endif
        return .other
    }

    private func firebaseReadableError(_ error: Error) -> String {
        #if canImport(FirebaseAuth)
        if let authError = error as NSError?, authError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: authError.code) {
            switch code {
            case .wrongPassword, .invalidCredential, .userNotFound:
                return localized("Неверный email или пароль")
            case .invalidEmail:
                return localized("Некорректный email")
            case .emailAlreadyInUse:
                return localized("Пользователь уже существует")
            case .weakPassword:
                return localized("Слишком слабый пароль")
            case .networkError:
                return localized("Проблема сети. Попробуйте ещё раз")
            default:
                return localized("Что-то пошло не так. Попробуйте ещё раз.")
            }
        }
        #endif
        return userFacingTransportError(error)
    }

    private func userFacingTransportError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .callIsActive:
                return localized("Проблема сети. Попробуйте ещё раз")
            default:
                return localized("Что-то пошло не так. Попробуйте ещё раз.")
            }
        }
        return localized("Что-то пошло не так. Попробуйте ещё раз.")
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func localizedStatusError(_ code: Int) -> String {
        String(format: localized("Ошибка: %d"), locale: Locale.current, code)
    }

    static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms: [UInt8] = Array(repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        #if canImport(CryptoKit)
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
        #else
        return input
        #endif
    }
}
