import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var testState: TestState = .idle
    @FocusState private var focusedField: Field?

    private enum Field {
        case server
        case username
    }

    private enum TestState: Equatable {
        case idle
        case running
        case allowed(String)
        case denied(String)
        case failed(String)
    }

    private var serverProblem: String? {
        settings.serverAddressProblem(for: settings.serverAddress)
    }

    private var canTest: Bool {
        settings.isConfigured && serverProblem == nil && testState != .running
    }

    var body: some View {
        List {
            serverSection
            usernameSection
            connectionSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.grouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: settings.serverAddress) { _, _ in resetTest() }
        .onChange(of: settings.username) { _, _ in resetTest() }
    }

    // MARK: - 服务器

    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField("https://example.com", text: $settings.serverAddress)
                    .font(.system(size: 15, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .server)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }

                if let problem = serverProblem {
                    inlineNote(problem, color: .danger, icon: "exclamationmark.circle.fill")
                }
            }
            .padding(.vertical, 3)
        } header: {
            Text("服务器地址")
        } footer: {
            Text("填写后端根地址，只填到端口为止，不要带路径。仅支持 https。")
        }
    }

    // MARK: - 用户名

    private var usernameSection: some View {
        Section {
            TextField("username", text: $settings.username)
                .font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .submitLabel(.done)
                .padding(.vertical, 3)
        } header: {
            Text("用户名")
        } footer: {
            Text("服务端用它识别调用方，需要事先加入允许名单，否则会提示「功能暂时没开通」。")
        }
    }

    // MARK: - 连接测试

    private var connectionSection: some View {
        Section {
            Button {
                runTest()
            } label: {
                HStack(spacing: 8) {
                    if testState == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(testState == .running ? "正在测试…" : "测试连接")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(canTest || testState == .running ? Color.accentColor : Color.sub)
            }
            .disabled(!canTest)
            .padding(.vertical, 2)

            switch testState {
            case .idle:
                EmptyView()
            case .running:
                EmptyView()
            case .allowed(let message):
                resultRow(message, detail: "地址可达，且已在允许名单内", color: .success, icon: "checkmark.circle.fill")
            case .denied(let message):
                resultRow(message, detail: "地址可达，但这个用户名没有权限", color: .caution, icon: "exclamationmark.triangle.fill")
            case .failed(let message):
                resultRow(message, detail: nil, color: .danger, icon: "xmark.circle.fill")
            }
        } header: {
            Text("连接")
        } footer: {
            if !settings.isConfigured {
                Text("填完上面两项后才能测试。")
            } else if serverProblem != nil {
                Text("地址不合法，请先修正。")
            } else {
                Text("同时验证地址是否可达、用户名是否被允许。")
            }
        }
    }

    private func resultRow(_ message: String, detail: String?, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                    .font(.system(size: 15))
                Spacer()
                Text(Self.versionString)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Color.sub)
            }
            .padding(.vertical, 2)
        } footer: {
            Text("修改后立即生效，书库会自动重新加载。")
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - 辅助

    private func inlineNote(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5))
                .lineSpacing(2)
        }
        .foregroundStyle(color)
    }

    private func resetTest() {
        testState = .idle
    }

    private func runTest() {
        focusedField = nil
        testState = .running

        Task {
            let result = await APIClient.shared.testConnection()
            await MainActor.run {
                switch result {
                case .allowed(let message):
                    testState = .allowed(message)
                case .denied(let message):
                    testState = .denied(message)
                case .failed(let message):
                    testState = .failed(message)
                }
            }
        }
    }
}

#Preview("空配置") {
    NavigationStack {
        SettingsView()
    }
}
