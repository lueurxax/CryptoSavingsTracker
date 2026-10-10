import Testing
@testable import CryptoSavingsTracker

struct TatumEnvironmentTests {
    @Test("Development uses an isolated Keychain service")
    func developmentUsesIsolatedKeychainService() {
        #expect(TatumEnvironment.development.keychainService == "tatum.development")
    }

    @Test("Production uses an isolated Keychain service")
    func productionUsesIsolatedKeychainService() {
        #expect(TatumEnvironment.production.keychainService == "tatum.production")
    }

    @Test("Configured environment takes precedence over the build fallback")
    func configuredEnvironmentTakesPrecedence() {
        #expect(TatumEnvironment.resolve(configuredValue: "production", isDebugBuild: true) == .production)
        #expect(TatumEnvironment.resolve(configuredValue: "development", isDebugBuild: false) == .development)
    }

    @Test("Missing or invalid configuration fails closed to the build environment")
    func invalidConfigurationUsesBuildFallback() {
        #expect(TatumEnvironment.resolve(configuredValue: nil, isDebugBuild: true) == .development)
        #expect(TatumEnvironment.resolve(configuredValue: "invalid", isDebugBuild: false) == .production)
    }
}
