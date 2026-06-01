import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum CustomProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .custom,
            metadata: ProviderMetadata(
                id: .custom,
                displayName: "Custom",
                sessionLabel: "Primary quota",
                weeklyLabel: "Secondary quota",
                opusLabel: "Tertiary quota",
                supportsOpus: true,
                supportsCredits: true,
                creditsHint: "Custom script cost or quota output.",
                toggleTitle: "Show Custom usage",
                cliName: "custom",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .custom,
                iconResourceName: "ProviderIcon-custom",
                color: ProviderColor(red: 0.22, green: 0.55, blue: 0.76)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Custom provider cost history is supplied by the configured script only." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [CustomScriptFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "custom",
                aliases: ["script"],
                versionDetector: nil))
    }
}

struct CustomScriptFetchStrategy: ProviderFetchStrategy {
    let id: String = "custom.script"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard let scriptPath = context.settings?.custom?.scriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scriptPath.isEmpty
        else {
            return false
        }
        let expanded = Self.expandedPath(scriptPath)
        return FileManager.default.isReadableFile(atPath: expanded)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let usage = try await CustomProviderScriptRunner.fetchUsage(
            settings: context.settings?.custom,
            environment: context.env)
        return self.makeResult(
            usage: usage,
            sourceLabel: "script")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func expandedPath(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst()) }
        return (path as NSString).expandingTildeInPath
    }
}
