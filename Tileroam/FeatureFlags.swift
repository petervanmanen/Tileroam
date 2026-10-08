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

    /// Route planning: on iPhone and iPad. Not in the Mac app, because the on-device router
    /// (valhalla-mobile) isn't built for the Mac.
    #if targetEnvironment(macCatalyst)
    static let routePlanning = false
    #else
    static let routePlanning = true
    #endif

    /// The Climbs challenge (tab, Statistics, climbs in planning and the year in review). Off
    /// for now: no climbs are downloaded or matched (`ClimbData.index` is nil). Set to true to
    /// bring it back; docs/CLIMBS.md describes how it works.
    static let climbs = false
}
