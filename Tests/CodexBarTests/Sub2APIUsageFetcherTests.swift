import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct Sub2APIUsageFetcherTests {
    @Test
    func `usage URL defaults to v1 usage endpoint`() throws {
        let versionedBaseURL = try #require(URL(string: "https://sub.cxc2.cn/v1"))

        #expect(Sub2APISettingsReader.defaultBaseURL.absoluteString == "https://sub.cxc2.cn")
        #expect(Sub2APIUsageFetcher._usageURLForTesting(
            baseURL: Sub2APISettingsReader.defaultBaseURL).absoluteString == "https://sub.cxc2.cn/v1/usage")
        #expect(Sub2APIUsageFetcher._usageURLForTesting(
            baseURL: versionedBaseURL).absoluteString == "https://sub.cxc2.cn/v1/usage")
    }

    @Test
    func `parses sub2api usage response`() throws {
        let snapshot = try Sub2APIUsageFetcher._parseSnapshotForTesting(
            Data(Self.sampleJSON.utf8),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.planName == "codex-订阅")
        #expect(snapshot.unit == "USD")
        #expect(snapshot.subscription.dailyLimitUSD == 100)
        #expect(snapshot.subscription.dailyUsageUSD == 0.650366)
        #expect(snapshot.subscription.weeklyLimitUSD == 600)
        #expect(snapshot.subscription.weeklyUsageUSD == 29.0493785)
        #expect(snapshot.usage.today.requests == 16)
        #expect(snapshot.usage.today.totalTokens == 416_105)
        #expect(snapshot.usage.total.actualCost == 319.22956665)
        #expect(snapshot.modelStats.first?.model == "gpt-5.5")
        #expect(snapshot.dailyUsage.first?.actualCost == 0.650366)
        #expect(usage.primary?.usedPercent == 0.650366)
        #expect(usage.primary?.resetDescription == "$0.65 / $100.00")
        let weeklyPercent = try #require(usage.secondary?.usedPercent)
        #expect(abs(weeklyPercent - 4.841563083333333) < 0.000001)
        #expect(usage.tertiary?.resetDescription == "monthly $29.05")
        #expect(usage.providerCost?.used == 0.650366)
        #expect(usage.providerCost?.limit == 100)
        #expect(usage.sub2APIUsage?.planName == "codex-订阅")
        #expect(usage.identity?.providerID == .sub2api)
        #expect(usage.identity?.accountOrganization == "codex-订阅")
        #expect(usage.identity?.loginMethod == "codex-订阅")
        #expect(usage.extraRateWindows == nil)

        let cost = try #require(usage.sub2APIUsage?.toCostUsageTokenSnapshot())
        #expect(cost.daily.count == 1)
        #expect(cost.daily.first?.date == "2026-06-02")
        #expect(cost.daily.first?.costUSD == 0.650366)
        #expect(cost.daily.first?.modelBreakdowns == nil)
        #expect(cost.last30DaysCostUSD == 0.650366)
    }

    @Test
    func `fetch sends bearer token`() async throws {
        defer {
            Sub2APIStubURLProtocol.handler = nil
            Sub2APIStubURLProtocol.requests = []
        }
        Sub2APIStubURLProtocol.requests = []
        Sub2APIStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sub2-test")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            return try Self.makeResponse(url: url, body: Self.sampleJSON)
        }

        let baseURL = try #require(URL(string: "https://sub.cxc2.cn"))
        let snapshot = try await Sub2APIUsageFetcher.fetchUsage(
            apiKey: "sub2-test",
            baseURL: baseURL,
            transport: Self.makeSession())

        #expect(snapshot.usage.today.requests == 16)
        #expect(Sub2APIStubURLProtocol.requests.map(\.url?.absoluteString) == ["https://sub.cxc2.cn/v1/usage"])
    }

    @Test
    func `settings reader and token resolver use SUB2API API key`() {
        let env = [Sub2APISettingsReader.apiKeyEnvironmentKey: "  sub2-token  "]

        #expect(Sub2APISettingsReader.apiKey(environment: env) == "sub2-token")
        #expect(ProviderTokenResolver.sub2APIToken(environment: env) == "sub2-token")
        #expect(ProviderTokenResolver.sub2APIResolution(environment: env)?.source == .environment)
    }

    @Test
    func `config API key and base URL feed sub2api environment`() {
        let config = ProviderConfig(
            id: .sub2api,
            apiKey: "config-token",
            enterpriseHost: "https://sub.example.com")
        let env = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [:],
            provider: .sub2api,
            config: config)

        #expect(env[Sub2APISettingsReader.apiKeyEnvironmentKey] == "config-token")
        #expect(env[Sub2APISettingsReader.baseURLEnvironmentKey] == "https://sub.example.com")
        #expect(ProviderTokenResolver.sub2APIToken(environment: env) == "config-token")
        #expect(Sub2APISettingsReader.baseURL(environment: env).absoluteString == "https://sub.example.com")
    }

    @Test
    func `descriptor is registered`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .sub2api)

        #expect(descriptor.id == .sub2api)
        #expect(descriptor.metadata.displayName == "Sub2API")
        #expect(descriptor.metadata.defaultEnabled == false)
        #expect(descriptor.tokenCost.supportsTokenCost)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])
        #expect(ProviderDescriptorRegistry.cliNameMap["sub2api"] == .sub2api)
        #expect(ProviderDescriptorRegistry.cliNameMap["sub2"] == .sub2api)
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Sub2APIStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int = 200) throws -> (HTTPURLResponse, Data)
    {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])
        else {
            throw URLError(.badServerResponse)
        }
        return (response, Data(body.utf8))
    }

    private static let sampleJSON = """
    {
      "daily_usage": [
        {
          "date": "2026-06-02",
          "requests": 16,
          "total_tokens": 416105,
          "cost": 0.650366,
          "actual_cost": 0.650366
        }
      ],
      "isValid": true,
      "mode": "unrestricted",
      "model_stats": [
        {
          "model": "gpt-5.5",
          "requests": 1900,
          "total_tokens": 233450414,
          "cost": 305.812253,
          "actual_cost": 305.812253
        }
      ],
      "planName": "codex-订阅",
      "remaining": 99.349634,
      "subscription": {
        "daily_limit_usd": 100,
        "daily_usage_usd": 0.650366,
        "expires_at": "2029-02-18T19:41:40.583733+08:00",
        "monthly_limit_usd": 0,
        "monthly_usage_usd": 29.0493785,
        "weekly_limit_usd": 600,
        "weekly_usage_usd": 29.0493785
      },
      "unit": "USD",
      "usage": {
        "average_duration_ms": 16026.923846823325,
        "rpm": 0,
        "today": {
          "actual_cost": 0.650366,
          "cache_creation_tokens": 0,
          "cache_read_tokens": 272896,
          "cost": 0.650366,
          "input_tokens": 138690,
          "output_tokens": 4519,
          "requests": 16,
          "total_tokens": 416105
        },
        "total": {
          "actual_cost": 319.22956665,
          "cache_creation_tokens": 0,
          "cache_read_tokens": 232238720,
          "cost": 319.22956665,
          "input_tokens": 14141294,
          "output_tokens": 1501396,
          "requests": 2298,
          "total_tokens": 247881410
        },
        "tpm": 13220
      }
    }
    """
}

final class Sub2APIStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "sub.cxc2.cn"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(self.request)
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
