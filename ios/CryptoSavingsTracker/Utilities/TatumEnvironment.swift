import Foundation

enum TatumEnvironment: String {
    case development
    case production

    var keychainService: String {
        "tatum.\(rawValue)"
    }

    static var current: TatumEnvironment {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif

        return resolve(
            configuredValue: Bundle.main.object(forInfoDictionaryKey: "TatumEnvironment") as? String,
            isDebugBuild: isDebugBuild
        )
    }

    static func resolve(configuredValue: String?, isDebugBuild: Bool) -> TatumEnvironment {
        if let configuredValue,
           let environment = TatumEnvironment(rawValue: configuredValue.lowercased()) {
            return environment
        }

        return isDebugBuild ? .development : .production
    }
}
