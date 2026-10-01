import Foundation

/// Features that can be switched off per build configuration.
enum FeatureFlags {
    /// The Strava connection. On when the `STRAVA` compilation condition is set (Debug and
    /// Release); remove the condition to build without Strava.
    #if STRAVA
    static let strava = true
    #else
    static let strava = false
    #endif
}
