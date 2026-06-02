import CodexBarCore
import Foundation

extension SettingsStore {
    var customScriptPath: String {
        get { self.configSnapshot.providerConfig(for: .custom)?.sanitizedCustomScriptPath ?? "" }
        set {
            self.updateProviderConfig(provider: .custom) { entry in
                entry.customScriptPath = self.normalizedConfigValue(newValue)
            }
            self.logProviderModeChange(provider: .custom, field: "scriptPath", value: newValue)
        }
    }

    var customScriptArgumentsText: String {
        get {
            self.configSnapshot.providerConfig(for: .custom)?
                .sanitizedCustomScriptArguments
                .joined(separator: "\n") ?? ""
        }
        set {
            let arguments = newValue
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.updateProviderConfig(provider: .custom) { entry in
                entry.customScriptArguments = arguments.isEmpty ? nil : arguments
            }
            self.logProviderModeChange(provider: .custom, field: "scriptArguments", value: "\(arguments.count)")
        }
    }

    var customScriptTimeoutText: String {
        get {
            let timeout = self.configSnapshot.providerConfig(for: .custom)?
                .sanitizedCustomScriptTimeoutSeconds ?? CustomProviderSettingsDefaults.timeoutSeconds
            return String(format: "%.0f", timeout)
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let timeout = Double(trimmed)
                .map(CustomProviderSettingsDefaults.clampedTimeout)
            self.updateProviderConfig(provider: .custom) { entry in
                entry.customScriptTimeoutSeconds = timeout
            }
            self.logProviderModeChange(provider: .custom, field: "scriptTimeoutSeconds", value: trimmed)
        }
    }

    func customSettingsSnapshot() -> ProviderSettingsSnapshot.CustomProviderSettings {
        let timeout = self.configSnapshot.providerConfig(for: .custom)?
            .sanitizedCustomScriptTimeoutSeconds ?? CustomProviderSettingsDefaults.timeoutSeconds
        return ProviderSettingsSnapshot.CustomProviderSettings(
            scriptPath: self.customScriptPath,
            arguments: self.configSnapshot.providerConfig(for: .custom)?.sanitizedCustomScriptArguments ?? [],
            timeoutSeconds: timeout)
    }
}
