import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var remote: SpotifyRemote
    @FocusState private var focused: Field?

    private enum Field {
        case host
        case port
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Settings")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Spotify")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                        Text(remote.isSignedIn ? "Signed in" : "Not signed in")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.82))
                        SolidButton(
                            title: remote.isAuthorizing ? "Waiting" : (remote.isSignedIn ? "Sign out" : "Sign in"),
                            enabled: !remote.isAuthorizing
                        ) {
                            if remote.isSignedIn {
                                remote.signOut()
                            } else {
                                remote.signIn()
                            }
                        }
                        if let error = remote.lastError {
                            Text(error)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 1, green: 0.67, blue: 0.64))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ubuntu")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                        fieldLabel("Ubuntu address")
                        TextField(
                            "",
                            text: $settings.ubuntuHost,
                            prompt: Text("192.168.1.20").foregroundColor(Color.white.opacity(0.7))
                        )
                        .focused($focused, equals: .host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .fieldChrome(focused: focused == .host)
                        Text("The computer's address on your network, for example 192.168.1.20.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                        fieldLabel("Port")
                        TextField(
                            "",
                            text: $settings.ubuntuPort,
                            prompt: Text("8765").foregroundColor(Color.white.opacity(0.7))
                        )
                        .focused($focused, equals: .port)
                        .keyboardType(.numberPad)
                        .fieldChrome(focused: focused == .port)
                        .onChange(of: settings.ubuntuPort) { value in
                            let digits = String(value.filter(\.isNumber).prefix(5))
                            if digits != value {
                                settings.ubuntuPort = digits
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.9))
    }
}

private extension View {
    func fieldChrome(focused: Bool) -> some View {
        self
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.85 : 0.22), lineWidth: 1)
            }
    }
}
