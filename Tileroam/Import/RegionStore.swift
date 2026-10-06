import Foundation
import Observation

/// The municipality and postcode boundaries of the countries the activities pass through
/// (Apple-hosted asset packs, see `RegionAssets`), and which countries those are.
@MainActor
@Observable
final class RegionStore {
    /// Boundaries of the switched-on countries; loaded in the background, nil until ready.
    private(set) var regions: RegionData?
    private(set) var isLoading = false
    /// Countries whose municipalities and postcodes are shown and counted.
    private(set) var enabledCountries: Set<String> = []
    /// Set when the boundaries of some countries couldn't be downloaded; retried on the next refresh.
    private(set) var error: String?
    /// Apple's error for the first failed country, shown in small print for diagnosis.
    private(set) var errorDetail: String?

    /// Called after the boundaries (re)loaded, so the owner can redraw and count again.
    @ObservationIgnored var onLoaded: () -> Void = {}

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Countries whose boundaries couldn't be downloaded.
    @ObservationIgnored private var failed = Set<String>()
    @ObservationIgnored private var scannedIDs = Set<String>()
    @ObservationIgnored private var pruneAfterCount = false
    private static let countriesKey = "enabledCountries"

    /// Waits for the boundaries (those that could be downloaded).
    func loaded() async -> RegionData {
        while true {
            if let regions, !isLoading { return regions }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Tries the failed downloads again (the "Try Again" button, and every refresh after a failure).
    func retry() {
        guard !isLoading else { return }
        load()
    }

    func load() {
        task?.cancel()
        isLoading = true
        let countries = enabledCountries
        task = Task {
            // Boundaries are Apple-hosted asset packs: download the missing countries first.
            let availability = await RegionAssets.makeAvailable(countries)
            guard !Task.isCancelled else { return }
            let data = await Task.detached(priority: .userInitiated) {
                RegionData.load(countries: availability.available)
            }.value
            guard !Task.isCancelled else { return }
            regions = data
            failed = Set(availability.failed.keys)
            let failedNames = availability.failed.keys.compactMap { Country.named($0)?.name }.sorted()
            error = failedNames.isEmpty ? nil : String(localized:
                "Couldn't load the municipalities and postcodes of \(failedNames.formatted(.list(type: .and))). Tileroam tries again when you open it.")
            errorDetail = availability.failed.sorted { $0.key < $1.key }.first.map { "\($0.key): \($0.value)" }
            isLoading = false
            onLoaded()
        }
    }

    /// At launch: the saved countries plus those of the activities (or the device's region when
    /// there are none).
    func chooseInitialCountries(_ activities: [Activity]) {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.countriesKey) {
            // Earlier versions had more countries; their boundaries are no longer available.
            enabledCountries = Set(saved).filter { Country.named($0) != nil }
        }
        // Countries follow the activities: drop any without visits after the first count
        // (earlier versions let the user switch countries on by hand).
        pruneAfterCount = true
        detectCountries(activities, load: false)
        if enabledCountries.isEmpty {
            let region = Locale.current.region?.identifier ?? "NL"
            enabledCountries = [Country.named(region) != nil ? region : "NL"]
        }
    }

    /// Switches on the countries new activities pass through, using the bundled outlines (or,
    /// without them, bounding boxes). Countries found near a border without a visited
    /// municipality are dropped again after the next count.
    func detectCountries(_ activities: [Activity], load: Bool = true) {
        let new = activities.filter { !scannedIDs.contains($0.id) && $0.isVirtual != true }
        scannedIDs.formUnion(new.map(\.id))
        let tracks = new.map { $0.coordinates.map { GeoPoint(lat: $0.latitude, lon: $0.longitude) } }
        var found = Set<String>()
        if let outlines = CountryOutlines.bundled {
            found = outlines.countries(visitedBy: tracks)
        } else {
            for track in tracks {
                for p in track.enumerated().filter({ $0.offset % max(1, track.count / 8) == 0 }).map(\.element) {
                    for country in Country.all where country.contains(p) { found.insert(country.code) }
                }
            }
        }
        let updated = enabledCountries.union(found)
        guard updated != enabledCountries else { return }
        enabledCountries = updated
        pruneAfterCount = true
        UserDefaults.standard.set(Array(updated).sorted(), forKey: Self.countriesKey)
        if load { self.load() }
    }

    /// After the first count: keep only countries with visited municipalities (plus the device's region).
    func pruneUnvisitedCountries(visitedMunicipalities: Set<String>) {
        // Wait until every country is loaded, except those whose download failed.
        guard pruneAfterCount, let regions,
              Set(regions.countries) == enabledCountries.subtracting(failed) else { return }
        pruneAfterCount = false
        guard let keep = CountrySelection.pruned(enabled: enabledCountries, visitedMunicipalities: visitedMunicipalities,
                                                 failed: failed) else { return }
        enabledCountries = keep
        UserDefaults.standard.set(Array(keep).sorted(), forKey: Self.countriesKey)
        load()
    }
}
