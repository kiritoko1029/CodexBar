import Foundation

public enum CustomProviderError: LocalizedError, Sendable {
    case missingScriptPath
    case scriptNotFound(String)
    case nodeNotFound
    case emptyOutput
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingScriptPath:
            "Custom provider script is not configured."
        case let .scriptNotFound(path):
            "Custom provider script was not found at \(path)."
        case .nodeNotFound:
            "Node.js was not found. Install node or make it available in PATH."
        case .emptyOutput:
            "Custom provider script produced no output."
        case let .parseFailed(message):
            "Custom provider parse error: \(message)"
        }
    }
}

public enum CustomProviderScriptRunner {
    public static func fetchUsage(
        settings: ProviderSettingsSnapshot.CustomProviderSettings?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        guard let settings,
              let scriptPath = settings.scriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scriptPath.isEmpty
        else {
            throw CustomProviderError.missingScriptPath
        }

        let expandedPath = Self.expandedPath(scriptPath)
        guard FileManager.default.isReadableFile(atPath: expandedPath) else {
            throw CustomProviderError.scriptNotFound(expandedPath)
        }

        var env = environment
        env["PATH"] = PathBuilder.effectivePATH(purposes: [.nodeTooling], env: environment)
        guard let node = Self.resolveNode(environment: env) else {
            throw CustomProviderError.nodeNotFound
        }

        let scriptURL = URL(fileURLWithPath: expandedPath)
        let result = try await SubprocessRunner.run(
            binary: node,
            arguments: [expandedPath] + settings.arguments,
            environment: env,
            timeout: settings.timeoutSeconds,
            currentDirectoryURL: scriptURL.deletingLastPathComponent(),
            label: "custom-provider")

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdout.isEmpty else {
            throw CustomProviderError.emptyOutput
        }
        guard let data = stdout.data(using: .utf8) else {
            throw CustomProviderError.parseFailed("Script output is not valid UTF-8.")
        }
        return try CustomUsageParser.parse(data: data, now: now)
    }

    private static func resolveNode(environment: [String: String]) -> String? {
        if let override = environment["CODEXBAR_NODE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override)
        {
            return override
        }
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":").map(String.init) {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent("node").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return ShellCommandLocator.commandV(
            "node",
            environment["SHELL"],
            2.0,
            .default)
    }

    private static func expandedPath(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst()) }
        return (path as NSString).expandingTildeInPath
    }
}

public enum CustomUsageParser {
    public static func parse(data: Data, now: Date = Date()) throws -> UsageSnapshot {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(Self.decodeDate)
            let payload = try decoder.decode(CustomProviderPayload.self, from: data)
            return try payload.toUsageSnapshot(now: now)
        } catch let error as CustomProviderError {
            throw error
        } catch {
            throw CustomProviderError.parseFailed(error.localizedDescription)
        }
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: seconds)
        }
        let text = try container.decode(String.self)
        if let date = CustomDateParser.parse(text) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported date value '\(text)'.")
    }
}

private struct CustomProviderPayload: Decodable {
    let primary: CustomRateWindowPayload?
    let secondary: CustomRateWindowPayload?
    let tertiary: CustomRateWindowPayload?
    let extraRateWindows: [CustomNamedRateWindowPayload]?
    let cost: CustomCostPayload?
    let providerCost: CustomCostPayload?
    let identity: CustomIdentityPayload?
    let updatedAt: Date?

    func toUsageSnapshot(now: Date) throws -> UsageSnapshot {
        let primary = self.primary?.toRateWindow()
        let secondary = self.secondary?.toRateWindow()
        let tertiary = self.tertiary?.toRateWindow()
        let extraWindows = self.extraRateWindows?.compactMap(\.namedRateWindow)
        guard primary != nil || secondary != nil || tertiary != nil || !(extraWindows?.isEmpty ?? true) else {
            throw CustomProviderError.parseFailed(
                "Script JSON must include at least one rate window: primary, secondary, tertiary, or extraRateWindows.")
        }

        let updatedAt = self.updatedAt ?? now
        let cost = self.providerCost ?? self.cost
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: (extraWindows?.isEmpty == false) ? extraWindows : nil,
            providerCost: cost?.toProviderCostSnapshot(updatedAt: updatedAt),
            updatedAt: updatedAt,
            identity: self.identity?.toIdentitySnapshot())
    }
}

private struct CustomRateWindowPayload: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?
    let nextRegenPercent: Double?

    func toRateWindow() -> RateWindow {
        RateWindow(
            usedPercent: Self.clampedPercent(self.usedPercent),
            windowMinutes: self.windowMinutes,
            resetsAt: self.resetsAt,
            resetDescription: Self.clean(self.resetDescription),
            nextRegenPercent: self.nextRegenPercent.map(Self.clampedPercent))
    }

    private static func clampedPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private struct CustomNamedRateWindowPayload: Decodable {
    let id: String?
    let title: String?
    let window: CustomRateWindowPayload?
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?
    let nextRegenPercent: Double?

    var namedRateWindow: NamedRateWindow? {
        guard let id = Self.clean(self.id),
              let title = Self.clean(self.title)
        else {
            return nil
        }
        let window = self.window?.toRateWindow() ?? self.inlineWindow
        guard let window else { return nil }
        return NamedRateWindow(id: id, title: title, window: window)
    }

    private var inlineWindow: RateWindow? {
        guard let usedPercent else { return nil }
        return RateWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowMinutes: self.windowMinutes,
            resetsAt: self.resetsAt,
            resetDescription: Self.clean(self.resetDescription),
            nextRegenPercent: self.nextRegenPercent.map { min(100, max(0, $0)) })
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private struct CustomCostPayload: Decodable {
    let used: Double
    let limit: Double
    let currencyCode: String?
    let period: String?
    let resetsAt: Date?
    let nextRegenAmount: Double?
    let updatedAt: Date?

    func toProviderCostSnapshot(updatedAt fallbackUpdatedAt: Date) -> ProviderCostSnapshot? {
        guard self.used.isFinite,
              self.limit.isFinite,
              self.limit > 0
        else {
            return nil
        }
        return ProviderCostSnapshot(
            used: max(0, self.used),
            limit: self.limit,
            currencyCode: Self.clean(self.currencyCode) ?? "USD",
            period: Self.clean(self.period),
            resetsAt: self.resetsAt,
            nextRegenAmount: self.nextRegenAmount,
            updatedAt: self.updatedAt ?? fallbackUpdatedAt)
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private struct CustomIdentityPayload: Decodable {
    let accountEmail: String?
    let accountOrganization: String?
    let loginMethod: String?

    func toIdentitySnapshot() -> ProviderIdentitySnapshot? {
        let email = Self.clean(self.accountEmail)
        let organization = Self.clean(self.accountOrganization)
        let method = Self.clean(self.loginMethod)
        guard email != nil || organization != nil || method != nil else { return nil }
        return ProviderIdentitySnapshot(
            providerID: .custom,
            accountEmail: email,
            accountOrganization: organization,
            loginMethod: method)
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private final class CustomISO8601FormatterBox: @unchecked Sendable {
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

private enum CustomDateParser {
    private static let iso8601 = CustomISO8601FormatterBox()

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
