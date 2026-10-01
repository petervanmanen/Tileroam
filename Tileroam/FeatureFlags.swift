import Foundation

/// Features that can be switched off per build configuration.
enum FeatureFlags {
    /// The Strava connection. On when the `STRAVA` compilation condition is set (Debug builds);
    /// off in Release/App Store builds, which then contain no Strava UI, data or secrets.
    #if STRAVA
    static let strava = true
    #else
    static let strava = false
    #endif
}
