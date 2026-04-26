import SwiftUI

struct AppAppearance: Equatable, Sendable {
    static let storageKey = "mvp.settings.appearance"

    let rawValue: String

    init(rawValue: String) {
        switch rawValue {
        case "light", "dark", "system":
            self.rawValue = rawValue
        default:
            self.rawValue = "system"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch rawValue {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}

enum AppIconSelection {
    static let darkAlternateIconName = "AppIconDark"

    static func iconName(for appearance: AppAppearance, systemColorScheme _: ColorScheme) -> String? {
        switch appearance.rawValue {
        case "dark":
            return darkAlternateIconName
        default:
            return nil
        }
    }
}

#if os(iOS)
@MainActor
enum AppIconSwitcher {
    static func apply(iconName: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error {
                AppLog.warning("Failed to switch app icon: \(error.localizedDescription)", category: .ui)
            }
        }
    }
}
#endif

struct AppAppearanceHost<Content: View>: View {
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = "system"
    @Environment(\.colorScheme) private var systemColorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue)
    }

    var body: some View {
        content
            .preferredColorScheme(appearance.preferredColorScheme)
            .task {
                applyAppIcon()
            }
            .onChange(of: appearanceRawValue) { _, _ in
                applyAppIcon()
            }
            .onChange(of: systemColorScheme) { _, _ in
                applyAppIcon()
            }
    }

    private func applyAppIcon() {
        #if os(iOS)
        let iconName = AppIconSelection.iconName(for: appearance, systemColorScheme: systemColorScheme)
        AppIconSwitcher.apply(iconName: iconName)
        #endif
    }
}
