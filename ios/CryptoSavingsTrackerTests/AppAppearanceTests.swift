import SwiftUI
import Testing
@testable import CryptoSavingsTracker

struct AppAppearanceTests {
    @Test("Explicit light appearance uses the primary app icon")
    func explicitLightAppearanceUsesPrimaryAppIcon() {
        let appearance = AppAppearance(rawValue: "light")

        #expect(appearance.preferredColorScheme == .light)
        #expect(AppIconSelection.iconName(for: appearance, systemColorScheme: .dark) == nil)
    }

    @Test("Explicit dark appearance uses the dark alternate app icon")
    func explicitDarkAppearanceUsesDarkAlternateAppIcon() {
        let appearance = AppAppearance(rawValue: "dark")

        #expect(appearance.preferredColorScheme == .dark)
        #expect(AppIconSelection.iconName(for: appearance, systemColorScheme: .light) == "AppIconDark")
    }

    @Test("System appearance leaves app icon selection to the system")
    func systemAppearanceLeavesAppIconSelectionToTheSystem() {
        let appearance = AppAppearance(rawValue: "system")

        #expect(appearance.preferredColorScheme == nil)
        #expect(AppIconSelection.iconName(for: appearance, systemColorScheme: .light) == nil)
        #expect(AppIconSelection.iconName(for: appearance, systemColorScheme: .dark) == nil)
    }
}
