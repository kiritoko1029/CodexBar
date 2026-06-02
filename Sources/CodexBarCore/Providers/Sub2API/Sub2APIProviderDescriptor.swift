import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum Sub2APIProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .sub2api,
            metadata: ProviderMetadata(
                id: .sub2api,
                displayName: "Sub2API",
                sessionLabel: "Daily spend",
                weeklyLabel: "Weekly spend",
                opusLabel: "Monthly spend",
                supportsOpus: true,
                supportsCredits: true,
                creditsHint: "Spend and quota data from the Sub2API /v1/usage endpoint.",
                toggleTitle: "Show Sub2API usage",
                cliName: "sub2api",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .sub2api,
                iconResourceName: "ProviderIcon-custom",
                color: ProviderColor(red: 0.18, green: 0.48, blue: 0.92)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: { "No Sub2API daily usage data returned by the provider API." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [Sub2APIAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "sub2api",
                aliases: ["sub2", "sub-api"],
                versionDetector: nil))
    }
}

struct Sub2APIAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "sub2api.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.sub2APIToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.sub2APIToken(environment: context.env) else {
            throw Sub2APIUsageError.missingCredentials
        }
        let usage = try await Sub2APIUsageFetcher.fetchUsage(
            apiKey: apiKey,
            baseURL: Sub2APISettingsReader.baseURL(environment: context.env))
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
