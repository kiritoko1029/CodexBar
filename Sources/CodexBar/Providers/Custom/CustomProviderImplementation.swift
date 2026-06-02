import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct CustomProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .custom

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            let scriptPath = context.settings.customScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !scriptPath.isEmpty else { return "script" }
            return URL(fileURLWithPath: scriptPath).lastPathComponent
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.customScriptPath
        _ = settings.customScriptArgumentsText
        _ = settings.customScriptTimeoutText
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        let scriptPath = context.settings.customScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scriptPath.isEmpty else { return false }
        let expanded = Self.expandedPath(scriptPath)
        return FileManager.default.isReadableFile(atPath: expanded)
    }

    @MainActor
    func defaultSourceLabel(context _: ProviderSourceLabelContext) -> String? {
        "script"
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .custom(context.settings.customSettingsSnapshot())
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "custom-script-path",
                title: "Script path",
                subtitle: "Node.js script that prints usage JSON to stdout.",
                kind: .plain,
                placeholder: "~/scripts/codexbar-custom-usage.js",
                binding: context.stringBinding(\.customScriptPath),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "custom-script-arguments",
                title: "Arguments",
                subtitle: "Optional. Enter one argument per line; they are passed after the script path.",
                kind: .plain,
                placeholder: "--profile\nwork",
                binding: context.stringBinding(\.customScriptArgumentsText),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "custom-script-timeout",
                title: "Timeout",
                subtitle: "Seconds to wait before stopping the script.",
                kind: .plain,
                placeholder: "30",
                binding: context.stringBinding(\.customScriptTimeoutText),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }

    private static func expandedPath(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst()) }
        return (path as NSString).expandingTildeInPath
    }
}
