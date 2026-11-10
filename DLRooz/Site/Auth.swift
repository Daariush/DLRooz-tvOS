import Foundation
import SwiftSoup

/// What the second login step asks for (the site asks new devices to confirm the account's mobile number;
/// the field may be an email address on some accounts).
struct SecondStep: Equatable, Sendable {
    /// Form field name, e.g. "mobile" or "email".
    let field: String
    /// The masked hint the site shows, e.g. "0912***0000".
    let hint: String
    /// The label next to the field on the site, e.g. «شماره موبایل».
    let label: String
    /// Text the site showed above the form, if any.
    let message: String?

    var isEmail: Bool { field.lowercased().contains("mail") || hint.contains("@") }
}

enum LoginPage: Equatable {
    case form
    case needsSecondStep(recaptchaPass: String, step: SecondStep)
    case wrongCredentials
    case redirecting
    case unknown(String?)
}

/// Classifies the HTML returned by `/user/login/`. Only alerts inside the form are login messages.
enum LoginParser {
    static func parse(_ html: String) -> LoginPage {
        guard let doc = try? Soup.parse(html) else { return .unknown(nil) }
        let form = doc.first("form")
        let alert = ((form ?? doc).first(form != nil ? ".alert" : ".alert-danger"))?.txt.nilIfBlank
        let key = alert.map(PersianText.normalize)
        if let key, key.contains("در حال انتقال") { return .redirecting }
        if let key, key.contains("نام کاربری یا رمز عبور اشتباه") { return .wrongCredentials }
        guard let form else { return .unknown(alert) }

        let recaptcha = form.first("input[name=recaptchaPass]")?.a("value") ?? ""
        let known: Set<String> = ["username", "password", "recaptchaPass"]
        // The extra visible field the site wants filled (mobile today; email on some accounts).
        let extra = form.all("input[name]").first { input in
            let type = input.a("type").lowercased()
            return !known.contains(input.a("name")) && type != "hidden" && type != "submit"
        }
        if let extra, !recaptcha.isEmpty {
            var label = ""
            if let row = extra.up?.up { label = row.first("label")?.txt ?? "" }
            let hint = extra.a("placeholder").nilIfBlank ?? extra.a("title")
            return .needsSecondStep(recaptchaPass: recaptcha,
                                    step: SecondStep(field: extra.a("name"), hint: hint, label: label, message: alert))
        }
        let names = Set(form.all("input[name]").map { $0.a("name") })
        if alert == nil && names == ["username", "password"] { return .form }
        return .unknown(alert)
    }
}

enum LoginResult: Equatable {
    case success
    case needsSecondStep(SecondStep)
    case wrongCredentials
    case failed(String)
}

struct Credentials: Codable {
    var username: String
    var password: String
    /// The second-step answer (mobile number or email) and its field name, if the site asked for one.
    var secondValue: String?
    var secondField: String?
}

/// The site's two-step login. Runs one login at a time; expired sessions are renewed silently with
/// the stored credentials, keeping the `sf` device cookie so the TV never counts as a new device.
actor AuthService {
    private let http: SiteHTTP
    private var jar: CookieJar { http.jar }
    private let credentialsKey = "site.credentials"

    init(http: SiteHTTP) { self.http = http }

    nonisolated var isLoggedIn: Bool { http.jar.value(SiteConfig.sessionCookie) != nil }
    nonisolated var sessionToken: String? { http.jar.value(SiteConfig.sessionCookie) }

    nonisolated var storedUsername: String? {
        Keychain.codable(Credentials.self, for: "site.credentials")?.username
    }

    /// `second` is the answer to the second step (mobile/email) when the caller already has it.
    func login(username: String, password: String, second: String?, secondField: String? = nil) async -> LoginResult {
        do {
            // Like a browser, load the form first: the site pairs its `sf` cookie with the `recaptchaPass` token.
            let form = try await http.get(SiteConfig.loginPath, requiresAuth: false)
            if !form.finalPath.hasPrefix(SiteConfig.loginPath) {
                // Already logged in: end that session, keep the device cookie, and log in as requested.
                _ = try? await http.get(SiteConfig.logoutPath, requiresAuth: false, retry: false)
                jar.clear(keep: [SiteConfig.deviceCookie])
                _ = try await http.get(SiteConfig.loginPath, requiresAuth: false)
            }
            let base = [("username", username), ("password", password)]
            var result: LoginResult
            var usedField = secondField
            switch try await post(base) {
            case .needsSecondStep(let token, let step):
                guard let second, !second.trimmed.isEmpty else { return .needsSecondStep(step) }
                usedField = step.field
                result = toResult(try await post(base + [("recaptchaPass", token), (step.field, second.trimmed)]))
            case let page:
                result = toResult(page)
            }
            if result == .success {
                Keychain.setCodable(Credentials(username: username, password: password,
                                                secondValue: second?.trimmed.nilIfBlank, secondField: usedField),
                                    for: credentialsKey)
                reportDevice()
            }
            return result
        } catch {
            return .failed((error as? SiteError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Renews an expired session with the stored credentials. False when the site refuses.
    func relogin() async -> Bool {
        guard let c = Keychain.codable(Credentials.self, for: credentialsKey) else {
            jar.clear(keep: [SiteConfig.deviceCookie])
            return false
        }
        let result = await login(username: c.username, password: c.password, second: c.secondValue, secondField: c.secondField)
        if result != .success {
            if result == .wrongCredentials { Keychain.set(nil, for: credentialsKey) }
            jar.clear(keep: [SiteConfig.deviceCookie])
        }
        return result == .success
    }

    func logout() async {
        Keychain.set(nil, for: credentialsKey)
        _ = try? await http.get(SiteConfig.logoutPath, requiresAuth: false, retry: false)
        jar.clear(keep: [SiteConfig.deviceCookie])
    }

    private func post(_ fields: [(String, String)]) async throws -> LoginPage {
        LoginParser.parse(try await http.postMultipart(SiteConfig.loginPath, fields: fields).body)
    }

    private func toResult(_ page: LoginPage) -> LoginResult {
        switch page {
        case .redirecting:
            return isLoggedIn ? .success : .failed(L("ورود انجام نشد", "Sign-in failed"))
        case .wrongCredentials:
            return .wrongCredentials
        case .needsSecondStep:
            return .failed(L("شماره موبایل یا ایمیل پذیرفته نشد", "The mobile number or email was not accepted"))
        case .form:
            return .failed(L("ورود انجام نشد", "Sign-in failed"))
        case .unknown(let text):
            return .failed(text ?? L("پاسخ ناشناخته از سایت", "Unexpected response from the site"))
        }
    }

    /// The website reports the screen once; we report the Apple TV 4K panel.
    private func reportDevice() {
        let http = self.http
        Task.detached {
            _ = try? await http.get("/json/device/?width=3840&height=2160&pixelRatio=1", requiresAuth: false)
        }
    }
}
