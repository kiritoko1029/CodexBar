import Foundation
import Testing
@testable import CodexBarCore

struct CustomProviderTests {
    @Test
    func `descriptor is registered and disabled by default`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .custom)

        #expect(descriptor.id == .custom)
        #expect(descriptor.metadata.displayName == "Custom")
        #expect(descriptor.metadata.defaultEnabled == false)
        #expect(descriptor.metadata.supportsCredits == true)
        #expect(descriptor.metadata.supportsOpus == true)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])
        #expect(ProviderDescriptorRegistry.cliNameMap["custom"] == .custom)
        #expect(ProviderDescriptorRegistry.cliNameMap["script"] == .custom)
    }

    @Test
    func `parses custom usage JSON`() throws {
        let json = """
        {
          "primary": {
            "usedPercent": 42.5,
            "windowMinutes": 300,
            "resetsAt": "2026-06-01T12:00:00Z",
            "resetDescription": "noon",
            "nextRegenPercent": 1.25
          },
          "secondary": {
            "usedPercent": -10
          },
          "tertiary": {
            "usedPercent": 130
          },
          "extraRateWindows": [
            {
              "id": "daily",
              "title": "Daily",
              "usedPercent": 25,
              "windowMinutes": 1440
            },
            {
              "id": "nested",
              "title": "Nested",
              "window": {
                "usedPercent": 30,
                "resetsAt": 1780318800
              }
            }
          ],
          "providerCost": {
            "used": 12.5,
            "limit": 100,
            "currencyCode": "USD",
            "period": "Monthly",
            "resetsAt": "2026-07-01T00:00:00.000Z",
            "nextRegenAmount": 2.5
          },
          "identity": {
            "accountEmail": "me@example.com",
            "accountOrganization": "Acme",
            "loginMethod": "Team"
          },
          "updatedAt": "2026-06-01T11:00:00Z"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let snapshot = try CustomUsageParser.parse(data: data, now: Date(timeIntervalSince1970: 0))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        #expect(snapshot.primary?.usedPercent == 42.5)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.primary?.resetsAt == formatter.date(from: "2026-06-01T12:00:00Z"))
        #expect(snapshot.primary?.resetDescription == "noon")
        #expect(snapshot.primary?.nextRegenPercent == 1.25)
        #expect(snapshot.secondary?.usedPercent == 0)
        #expect(snapshot.tertiary?.usedPercent == 100)
        #expect(snapshot.extraRateWindows?.count == 2)
        #expect(snapshot.extraRateWindows?.first?.id == "daily")
        #expect(snapshot.extraRateWindows?.first?.window.usedPercent == 25)
        #expect(snapshot.extraRateWindows?.last?.title == "Nested")
        #expect(snapshot.extraRateWindows?.last?.window.usedPercent == 30)
        #expect(snapshot.providerCost?.used == 12.5)
        #expect(snapshot.providerCost?.limit == 100)
        #expect(snapshot.providerCost?.currencyCode == "USD")
        #expect(snapshot.providerCost?.period == "Monthly")
        #expect(snapshot.providerCost?.resetsAt == fractionalFormatter.date(from: "2026-07-01T00:00:00.000Z"))
        #expect(snapshot.providerCost?.nextRegenAmount == 2.5)
        #expect(snapshot.updatedAt == formatter.date(from: "2026-06-01T11:00:00Z"))
        #expect(snapshot.identity(for: .custom)?.accountEmail == "me@example.com")
        #expect(snapshot.identity(for: .custom)?.accountOrganization == "Acme")
        #expect(snapshot.loginMethod(for: .custom) == "Team")
        #expect(snapshot.identity(for: .codex) == nil)
    }

    @Test
    func `cost alias falls back when provider cost is absent`() throws {
        let json = """
        {
          "primary": { "usedPercent": 5 },
          "cost": {
            "used": 3,
            "limit": 9,
            "currencyCode": "EUR"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let now = Date(timeIntervalSince1970: 42)
        let snapshot = try CustomUsageParser.parse(data: data, now: now)

        #expect(snapshot.primary?.usedPercent == 5)
        #expect(snapshot.providerCost?.used == 3)
        #expect(snapshot.providerCost?.limit == 9)
        #expect(snapshot.providerCost?.currencyCode == "EUR")
        #expect(snapshot.providerCost?.updatedAt == now)
    }

    @Test
    func `settings sanitize arguments and clamp timeout`() {
        let config = ProviderConfig(
            id: .custom,
            customScriptPath: "  '~/usage.js'  ",
            customScriptArguments: [" --profile ", "", " 'work' "],
            customScriptTimeoutSeconds: 999)

        #expect(config.sanitizedCustomScriptPath == "~/usage.js")
        #expect(config.sanitizedCustomScriptArguments == ["--profile", "work"])

        let settings = ProviderSettingsSnapshot.CustomProviderSettings(
            scriptPath: config.sanitizedCustomScriptPath,
            arguments: config.sanitizedCustomScriptArguments,
            timeoutSeconds: config.sanitizedCustomScriptTimeoutSeconds ?? 30)

        #expect(settings.scriptPath == "~/usage.js")
        #expect(settings.arguments == ["--profile", "work"])
        #expect(settings.timeoutSeconds == CustomProviderSettingsDefaults.maximumTimeoutSeconds)
    }
}
