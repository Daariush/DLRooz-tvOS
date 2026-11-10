import SwiftUI

/// First-run sign-in: username (or email) and password, then the site's second step when it asks
/// for the account's mobile number (or email) to confirm a new device.
struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings

    @State private var username = ""
    @State private var password = ""
    @State private var secondValue = ""
    @State private var secondStep: SecondStep?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case username, password, second, submit }

    var body: some View {
        HStack(spacing: 120) {
            VStack(alignment: .leading, spacing: 24) {
                Text("DL Rooz")
                    .font(.system(size: 96, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent, .orange], startPoint: .leading, endPoint: .trailing))
                Text(L("فیلم و سریال‌های دی‌ال‌روز، روی تلویزیون", "Your DLRooz movies and series, on the big screen"))
                    .font(.title3).foregroundStyle(Theme.secondaryText)
                Text(L("با نام کاربری و رمز حساب دی‌ال‌روز خود وارد شوید. رمز شما فقط در Keychain همین دستگاه ذخیره می‌شود.",
                       "Sign in with your DLRooz account. Your password is kept only in this Apple TV's Keychain."))
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                Picker(L("زبان", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
            }
            .frame(maxWidth: 700, alignment: .leading)

            VStack(spacing: 28) {
                if let step = secondStep {
                    secondStepFields(step)
                } else {
                    credentialFields
                }
                if let error {
                    Text(error).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
                }
                Button(action: submit) {
                    HStack(spacing: 16) {
                        if busy { ProgressView() }
                        Text(secondStep == nil ? L("ورود", "Sign In") : L("ادامه", "Continue"))
                            .frame(minWidth: 380)
                    }
                }
                .focused($focus, equals: .submit)
                .disabled(busy || !canSubmit)
                if secondStep != nil {
                    Button(L("بازگشت", "Back")) { secondStep = nil; secondValue = ""; error = nil }
                        .disabled(busy)
                }
            }
            .frame(width: 640)
        }
        .padding(80)
        .onAppear { focus = .username }
    }

    private var credentialFields: some View {
        VStack(spacing: 24) {
            TextField(L("نام کاربری یا ایمیل", "Username or email"), text: $username)
                .textContentType(.username)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focus, equals: .username)
                .onSubmit { focus = .password }
            SecureField(L("رمز عبور", "Password"), text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .onSubmit { focus = .submit }
        }
    }

    private func secondStepFields(_ step: SecondStep) -> some View {
        VStack(spacing: 20) {
            Image(systemName: step.isEmail ? "envelope.badge.shield.half.filled" : "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 64)).foregroundStyle(Theme.accent)
            Text(step.message ?? (step.isEmail
                ? L("برای تأیید این دستگاه، ایمیل حساب را کامل وارد کنید", "To confirm this device, enter your account's email address")
                : L("برای تأیید این دستگاه، شماره موبایل حساب را کامل وارد کنید", "To confirm this device, enter your account's full mobile number")))
                .multilineTextAlignment(.center)
            if !step.hint.isEmpty {
                Text(step.hint).font(.headline).environment(\.layoutDirection, .leftToRight)
                    .foregroundStyle(Theme.secondaryText)
            }
            TextField(step.label.nilIfBlank ?? (step.isEmail ? L("ایمیل", "Email") : L("شماره موبایل", "Mobile number")),
                      text: $secondValue)
                .keyboardType(step.isEmail ? .emailAddress : .numberPad)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focus, equals: .second)
                .onSubmit { focus = .submit }
        }
    }

    private var canSubmit: Bool {
        if secondStep != nil { return !secondValue.trimmed.isEmpty }
        return !username.trimmed.isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        busy = true
        error = nil
        let second = secondStep == nil ? nil : PersianText.digits(secondValue)
        Task {
            let result = await model.auth.login(username: username.trimmed, password: password, second: second,
                                                secondField: secondStep?.field)
            busy = false
            switch result {
            case .success:
                model.didSignIn()
            case .needsSecondStep(let step):
                secondStep = step
                focus = .second
            case .wrongCredentials:
                secondStep = nil
                error = L("نام کاربری یا رمز عبور اشتباه است", "Wrong username or password")
                focus = .password
            case .failed(let message):
                error = message
            }
        }
    }
}
