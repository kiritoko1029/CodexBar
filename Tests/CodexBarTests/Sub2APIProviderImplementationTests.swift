import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct Sub2APIProviderImplementationTests {
    @Test
    func `availability uses sub2api environment token`() throws {
        let settings = try Self.makeSettings(suite: "Sub2APIProviderImplementationTests-env")
        let implementation = Sub2APIProviderImplementation()

        let context = ProviderAvailabilityContext(
            provider: .sub2api,
            settings: settings,
            environment: [Sub2APISettingsReader.apiKeyEnvironmentKey: "env-token"])

        #expect(implementation.isAvailable(context: context))
    }

    @Test
    func `availability uses stored sub2api API token`() throws {
        let settings = try Self.makeSettings(suite: "Sub2APIProviderImplementationTests-settings")
        settings.sub2APIKey = "stored-token"
        let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .sub2api,
            config: settings.providerConfig(for: .sub2api))
        let implementation = Sub2APIProviderImplementation()

        let context = ProviderAvailabilityContext(provider: .sub2api, settings: settings, environment: environment)

        #expect(implementation.isAvailable(context: context))
    }

    @Test
    func `availability rejects missing sub2api API token`() throws {
        let settings = try Self.makeSettings(suite: "Sub2APIProviderImplementationTests-missing")
        settings.sub2APIKey = "   "
        let implementation = Sub2APIProviderImplementation()

        let context = ProviderAvailabilityContext(provider: .sub2api, settings: settings, environment: [:])

        #expect(!implementation.isAvailable(context: context))
    }

    private static func makeSettings(suite: String) throws -> SettingsStore {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }
}
