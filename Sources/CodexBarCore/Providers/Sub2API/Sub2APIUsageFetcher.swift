import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum Sub2APIUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case apiError(Int)
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Missing Sub2API API key. Set apiKey in ~/.codexbar/config.json or SUB2API_API_KEY."
        case let .apiError(statusCode):
            "Sub2API usage API error: HTTP \(statusCode)"
        case let .networkError(message):
            "Sub2API network error: \(message)"
        case let .parseFailed(message):
            "Failed to parse Sub2API usage response: \(message)"
        }
    }
}

public struct Sub2APIUsageSnapshot: Codable, Sendable, Equatable {
    public let planName: String?
    public let mode: String?
    public let unit: String
    public let remaining: Double?
    public let subscription: Subscription
    public let usage: Usage
    public let modelStats: [ModelStat]
    public let dailyUsage: [DailyUsage]
    public let updatedAt: Date

    public struct Subscription: Codable, Sendable, Equatable {
        public let dailyLimitUSD: Double
        public let dailyUsageUSD: Double
        public let weeklyLimitUSD: Double
        public let weeklyUsageUSD: Double
        public let monthlyLimitUSD: Double
        public let monthlyUsageUSD: Double
        public let expiresAt: Date?
    }

    public struct Usage: Codable, Sendable, Equatable {
        public let today: TokenUsage
        public let total: TokenUsage
        public let averageDurationMS: Double?
        public let rpm: Double?
        public let tpm: Double?
    }

    public struct TokenUsage: Codable, Sendable, Equatable {
        public let actualCost: Double
        public let cost: Double
        public let requests: Int
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let cacheCreationTokens: Int
        public let totalTokens: Int
    }

    public struct DailyUsage: Codable, Sendable, Equatable {
        public let date: String
        public let requests: Int
        public let totalTokens: Int
        public let cost: Double
        public let actualCost: Double
    }

    public struct ModelStat: Codable, Sendable, Equatable {
        public let model: String
        public let requests: Int
        public let totalTokens: Int
        public let cost: Double
        public let actualCost: Double
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let daily = Self.window(
            used: self.subscription.dailyUsageUSD,
            limit: self.subscription.dailyLimitUSD,
            minutes: 24 * 60,
            resetsAt: Self.nextLocalMidnight(after: self.updatedAt),
            detail: Self.moneyDetail(
                used: self.subscription.dailyUsageUSD,
                limit: self.subscription.dailyLimitUSD,
                unit: self.unit))
        let weekly = Self.window(
            used: self.subscription.weeklyUsageUSD,
            limit: self.subscription.weeklyLimitUSD,
            minutes: 7 * 24 * 60,
            resetsAt: Self.nextLocalWeekStart(after: self.updatedAt),
            detail: Self.moneyDetail(
                used: self.subscription.weeklyUsageUSD,
                limit: self.subscription.weeklyLimitUSD,
                unit: self.unit))
        let monthly = self.subscription.monthlyLimitUSD > 0
            ? Self.window(
                used: self.subscription.monthlyUsageUSD,
                limit: self.subscription.monthlyLimitUSD,
                minutes: nil,
                resetsAt: Self.nextLocalMonthStart(after: self.updatedAt),
                detail: Self.moneyDetail(
                    used: self.subscription.monthlyUsageUSD,
                    limit: self.subscription.monthlyLimitUSD,
                    unit: self.unit))
            : RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: self.subscription.expiresAt,
                resetDescription: "monthly \(Self.money(self.subscription.monthlyUsageUSD, unit: self.unit))")
        return UsageSnapshot(
            primary: daily,
            secondary: weekly,
            tertiary: monthly,
            extraRateWindows: nil,
            providerCost: self.providerCost,
            sub2APIUsage: self,
            updatedAt: self.updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .sub2api,
                accountEmail: nil,
                accountOrganization: self.planName,
                loginMethod: self.planName))
    }

    public func toCostUsageTokenSnapshot() -> CostUsageTokenSnapshot {
        let daily = self.dailyUsage.map { bucket in
            CostUsageDailyReport.Entry(
                date: bucket.date,
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                totalTokens: bucket.totalTokens,
                requestCount: bucket.requests,
                costUSD: bucket.actualCost,
                modelsUsed: nil,
                modelBreakdowns: nil)
        }
        let latest = daily.max { lhs, rhs in lhs.date < rhs.date }
        let historyCost = daily.reduce(0) { $0 + ($1.costUSD ?? 0) }
        let historyTokens = daily.compactMap(\.totalTokens).reduce(0, +)
        let historyRequests = daily.compactMap(\.requestCount).reduce(0, +)
        return CostUsageTokenSnapshot(
            sessionTokens: latest?.totalTokens ?? self.usage.today.totalTokens,
            sessionCostUSD: latest?.costUSD ?? self.usage.today.actualCost,
            sessionRequests: latest?.requestCount ?? self.usage.today.requests,
            last30DaysTokens: historyTokens > 0 ? historyTokens : nil,
            last30DaysCostUSD: historyCost,
            last30DaysRequests: historyRequests > 0 ? historyRequests : nil,
            currencyCode: self.unit,
            historyDays: daily.isEmpty ? 30 : max(1, min(365, daily.count)),
            historyLabel: "Subscription",
            daily: daily,
            updatedAt: self.updatedAt)
    }

    public var displayLines: [String] {
        var lines: [String] = []
        if let planName, !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Plan: \(planName)")
        }
        if let remaining {
            lines.append("Remaining: \(Self.money(remaining, unit: self.unit))")
        }
        if let expiresAt = self.subscription.expiresAt {
            lines.append("Expires: \(Self.dateString(expiresAt))")
        }
        lines.append(
            "Today: \(Self.money(self.usage.today.actualCost, unit: self.unit)) · " +
                "\(Self.formatInteger(self.usage.today.totalTokens)) tokens · " +
                "\(Self.formatInteger(self.usage.today.requests)) requests")
        lines.append(
            "Total: \(Self.money(self.usage.total.actualCost, unit: self.unit)) · " +
                "\(Self.formatInteger(self.usage.total.totalTokens)) tokens · " +
                "\(Self.formatInteger(self.usage.total.requests)) requests")
        if let tpm = self.usage.tpm, tpm > 0 {
            lines.append("TPM: \(Self.formatDecimal(tpm))")
        }
        if let rpm = self.usage.rpm, rpm > 0 {
            lines.append("RPM: \(Self.formatDecimal(rpm))")
        }
        if let duration = self.usage.averageDurationMS, duration > 0 {
            lines.append("Avg duration: \(Self.formatDuration(milliseconds: duration))")
        }
        return lines
    }

    private var providerCost: ProviderCostSnapshot? {
        let daily = self.subscription.dailyLimitUSD
        guard daily.isFinite, daily > 0 else { return nil }
        return ProviderCostSnapshot(
            used: max(0, self.subscription.dailyUsageUSD),
            limit: daily,
            currencyCode: self.unit.isEmpty ? "USD" : self.unit,
            period: "Daily",
            resetsAt: Self.nextLocalMidnight(after: self.updatedAt),
            updatedAt: self.updatedAt)
    }

    private static func window(
        used: Double,
        limit: Double,
        minutes: Int?,
        resetsAt: Date?,
        detail: String) -> RateWindow
    {
        let usedPercent = limit > 0
            ? (max(0, used) / limit * 100).clamped(to: 0...100)
            : 0
        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: minutes,
            resetsAt: resetsAt,
            resetDescription: detail)
    }

    private static func moneyDetail(used: Double, limit: Double, unit: String) -> String {
        "\(self.money(used, unit: unit)) / \(self.money(limit, unit: unit))"
    }

    private static func money(_ value: Double, unit: String) -> String {
        let currency = unit.isEmpty ? "USD" : unit
        if currency.uppercased() == "USD" {
            return UsageFormatter.usdString(value)
        }
        return "\(currency) \(String(format: "%.2f", value))"
    }

    public static func moneyString(_ value: Double, unit: String) -> String {
        self.money(value, unit: unit)
    }

    private static func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    private static func formatDuration(milliseconds: Double) -> String {
        let seconds = max(0.0, milliseconds) / 1000.0
        if seconds >= 10 {
            return "\(String(format: "%.0f", seconds))s"
        }
        return "\(String(format: "%.1f", seconds))s"
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func nextLocalMidnight(after date: Date) -> Date? {
        Calendar.current.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime)
    }

    private static func nextLocalWeekStart(after date: Date) -> Date? {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.date(byAdding: .weekOfYear, value: 1, to: start)
    }

    private static func nextLocalMonthStart(after date: Date) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month], from: date)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let start = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.date(byAdding: .month, value: 1, to: start)
    }
}

public enum Sub2APIUsageFetcher {
    private static let timeoutSeconds: TimeInterval = 15

    public static func fetchUsage(
        apiKey: String,
        baseURL: URL = Sub2APISettingsReader.defaultBaseURL,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        updatedAt: Date = Date()) async throws -> Sub2APIUsageSnapshot
    {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Sub2APIUsageError.missingCredentials
        }

        var request = URLRequest(url: self.usageURL(baseURL: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeoutSeconds
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request)
        } catch {
            throw Sub2APIUsageError.networkError(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Sub2APIUsageError.apiError(response.statusCode)
        }

        return try self.parseSnapshot(response.data, updatedAt: updatedAt)
    }

    public static func _parseSnapshotForTesting(_ data: Data, updatedAt: Date) throws -> Sub2APIUsageSnapshot {
        try self.parseSnapshot(data, updatedAt: updatedAt)
    }

    public static func _usageURLForTesting(baseURL: URL) -> URL {
        self.usageURL(baseURL: baseURL)
    }

    private static func usageURL(baseURL: URL) -> URL {
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let versionedBaseURL = path.split(separator: "/").last == "v1"
            ? baseURL
            : baseURL.appendingPathComponent("v1")
        return versionedBaseURL.appendingPathComponent("usage")
    }

    private static func parseSnapshot(_ data: Data, updatedAt: Date) throws -> Sub2APIUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        do {
            let decoded = try decoder.decode(Sub2APIUsageResponse.self, from: data)
            return decoded.toSnapshot(updatedAt: updatedAt)
        } catch let error as Sub2APIUsageError {
            throw error
        } catch {
            throw Sub2APIUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: seconds)
        }
        let text = try container.decode(String.self)
        if let date = Sub2APIDateParser.parse(text) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported date value '\(text)'.")
    }
}

private struct Sub2APIUsageResponse: Decodable {
    let isValid: Bool?
    let mode: String?
    let planName: String?
    let remaining: Double?
    let subscription: Subscription?
    let unit: String?
    let usage: Usage?
    let modelStats: [ModelStat]?
    let dailyUsage: [DailyUsage]?

    private enum CodingKeys: String, CodingKey {
        case isValid
        case mode
        case planName
        case remaining
        case subscription
        case unit
        case usage
        case modelStats = "model_stats"
        case dailyUsage = "daily_usage"
    }

    struct Subscription: Decodable {
        let dailyLimitUSD: Double?
        let dailyUsageUSD: Double?
        let weeklyLimitUSD: Double?
        let weeklyUsageUSD: Double?
        let monthlyLimitUSD: Double?
        let monthlyUsageUSD: Double?
        let expiresAt: Date?

        private enum CodingKeys: String, CodingKey {
            case dailyLimitUSD = "daily_limit_usd"
            case dailyUsageUSD = "daily_usage_usd"
            case weeklyLimitUSD = "weekly_limit_usd"
            case weeklyUsageUSD = "weekly_usage_usd"
            case monthlyLimitUSD = "monthly_limit_usd"
            case monthlyUsageUSD = "monthly_usage_usd"
            case expiresAt = "expires_at"
        }
    }

    struct Usage: Decodable {
        let averageDurationMS: Double?
        let rpm: Double?
        let tpm: Double?
        let today: TokenUsage?
        let total: TokenUsage?

        private enum CodingKeys: String, CodingKey {
            case averageDurationMS = "average_duration_ms"
            case rpm
            case tpm
            case today
            case total
        }
    }

    struct TokenUsage: Decodable {
        let actualCost: Double?
        let cacheCreationTokens: Int?
        let cacheReadTokens: Int?
        let cost: Double?
        let inputTokens: Int?
        let outputTokens: Int?
        let requests: Int?
        let totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case actualCost = "actual_cost"
            case cacheCreationTokens = "cache_creation_tokens"
            case cacheReadTokens = "cache_read_tokens"
            case cost
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case requests
            case totalTokens = "total_tokens"
        }
    }

    struct DailyUsage: Decodable {
        let date: String?
        let requests: Int?
        let totalTokens: Int?
        let cost: Double?
        let actualCost: Double?

        private enum CodingKeys: String, CodingKey {
            case date
            case requests
            case totalTokens = "total_tokens"
            case cost
            case actualCost = "actual_cost"
        }
    }

    struct ModelStat: Decodable {
        let model: String?
        let requests: Int?
        let totalTokens: Int?
        let cost: Double?
        let actualCost: Double?

        private enum CodingKeys: String, CodingKey {
            case model
            case requests
            case totalTokens = "total_tokens"
            case cost
            case actualCost = "actual_cost"
        }
    }

    func toSnapshot(updatedAt: Date) -> Sub2APIUsageSnapshot {
        Sub2APIUsageSnapshot(
            planName: self.clean(self.planName),
            mode: self.clean(self.mode),
            unit: self.clean(self.unit) ?? "USD",
            remaining: self.remaining,
            subscription: self.subscriptionSnapshot,
            usage: self.usageSnapshot,
            modelStats: self.modelStats?.map(Self.modelStatSnapshot).filter { !$0.model.isEmpty } ?? [],
            dailyUsage: self.dailyUsage?.map(Self.dailyUsageSnapshot).filter { !$0.date.isEmpty } ?? [],
            updatedAt: updatedAt)
    }

    private var subscriptionSnapshot: Sub2APIUsageSnapshot.Subscription {
        Sub2APIUsageSnapshot.Subscription(
            dailyLimitUSD: self.subscription?.dailyLimitUSD ?? 0,
            dailyUsageUSD: self.subscription?.dailyUsageUSD ?? 0,
            weeklyLimitUSD: self.subscription?.weeklyLimitUSD ?? 0,
            weeklyUsageUSD: self.subscription?.weeklyUsageUSD ?? 0,
            monthlyLimitUSD: self.subscription?.monthlyLimitUSD ?? 0,
            monthlyUsageUSD: self.subscription?.monthlyUsageUSD ?? 0,
            expiresAt: self.subscription?.expiresAt)
    }

    private var usageSnapshot: Sub2APIUsageSnapshot.Usage {
        let usage = self.usage
        return Sub2APIUsageSnapshot.Usage(
            today: Self.tokenUsageSnapshot(usage?.today),
            total: Self.tokenUsageSnapshot(usage?.total),
            averageDurationMS: usage?.averageDurationMS,
            rpm: usage?.rpm,
            tpm: usage?.tpm)
    }

    private static func tokenUsageSnapshot(_ usage: TokenUsage?) -> Sub2APIUsageSnapshot.TokenUsage {
        Sub2APIUsageSnapshot.TokenUsage(
            actualCost: usage?.actualCost ?? usage?.cost ?? 0,
            cost: usage?.cost ?? usage?.actualCost ?? 0,
            requests: usage?.requests ?? 0,
            inputTokens: usage?.inputTokens ?? 0,
            outputTokens: usage?.outputTokens ?? 0,
            cacheReadTokens: usage?.cacheReadTokens ?? 0,
            cacheCreationTokens: usage?.cacheCreationTokens ?? 0,
            totalTokens: usage?.totalTokens ?? 0)
    }

    private static func dailyUsageSnapshot(_ usage: DailyUsage) -> Sub2APIUsageSnapshot.DailyUsage {
        Sub2APIUsageSnapshot.DailyUsage(
            date: usage.date ?? "",
            requests: usage.requests ?? 0,
            totalTokens: usage.totalTokens ?? 0,
            cost: usage.cost ?? usage.actualCost ?? 0,
            actualCost: usage.actualCost ?? usage.cost ?? 0)
    }

    private static func modelStatSnapshot(_ stat: ModelStat) -> Sub2APIUsageSnapshot.ModelStat {
        Sub2APIUsageSnapshot.ModelStat(
            model: stat.model ?? "",
            requests: stat.requests ?? 0,
            totalTokens: stat.totalTokens ?? 0,
            cost: stat.cost ?? stat.actualCost ?? 0,
            actualCost: stat.actualCost ?? stat.cost ?? 0)
    }

    private func clean(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private final class Sub2APIISO8601FormatterBox: @unchecked Sendable {
    let lock = NSLock()
    let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum Sub2APIDateParser {
    private static let iso8601 = Sub2APIISO8601FormatterBox()

    static func parse(_ text: String) -> Date? {
        self.iso8601.lock.lock()
        defer { self.iso8601.lock.unlock() }
        return self.iso8601.withFractional.date(from: text)
            ?? self.iso8601.plain.date(from: text)
            ?? self.secondsSince1970(text)
    }

    private static func secondsSince1970(_ text: String) -> Date? {
        guard let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              seconds.isFinite
        else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }
}
