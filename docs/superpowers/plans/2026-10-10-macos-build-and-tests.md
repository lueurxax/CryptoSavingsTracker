# macOS compilation and tests

Fix the 13 platform diagnostics reported by the native macOS build, preserving existing source changes and staged changes.

- [x] Replace unguarded UIKit background colors with a shared system-color adapter. Preserve native UIKit colors on iOS and use native AppKit backgrounds on macOS.
- [x] Use the supported inset list style for both active and finished goal details on macOS; retain grouped inset lists on iOS.
- [x] Build the native macOS app and resolve any remaining compilation diagnostics.
- [x] Run the full native macOS unit/integration test scheme, fixing underlying test or app problems without skipping tests.
- [x] Check the iOS build/test suite after shared UI changes.
- [x] Review the focused patch and record final verification results and limitations.

The previous failed macOS compilation is the regression evidence for platform availability. Compilation and full tests are the meaningful checks for these color and style adapters; trivial forwarding getters do not need mirror tests. Test execution must use fixtures rather than live wallet services.
