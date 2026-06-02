import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct Sub2APIProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .sub2api

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.sub2APIKey
        _ = settings.sub2APIBaseURL
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        ProviderTokenResolver.sub2APIToken(environment: context.environment) != nil
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "sub2api-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. You can also provide SUB2API_API_KEY.",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.sub2APIKey),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "sub2api-open-usage",
                        title: "Open usage endpoint",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://sub.cxc2.cn/v1/usage") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "sub2api-base-url",
                title: "Base URL",
                subtitle: "Optional. Defaults to https://sub.cxc2.cn.",
                kind: .plain,
                placeholder: "https://sub.cxc2.cn",
                binding: context.stringBinding(\.sub2APIBaseURL),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
