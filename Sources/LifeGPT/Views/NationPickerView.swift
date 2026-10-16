import SwiftUI
import LifeCore

/// Search narrows bundled presets; typed country/region strings are never saved as authoritative identities.
struct NationPickerView: View {
    @Binding var selection: JurisdictionRef?
    let date: GameDate
    @State private var query = ""
    @State private var regionQuery = ""
    private let catalog = CountryCatalog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search nations or historical presets", text: $query)
            Picker("Nation", selection: Binding(get: { selection?.countryID ?? "" }, set: { value in
                selection = value.isEmpty ? nil : JurisdictionRef(countryID: value)
                regionQuery = ""
            })) {
                Text("Choose a nation").tag("")
                ForEach(visibleCountries) { country in
                    Text(country.name + (country.isHistorical ? " (historical)" : "")).tag(country.id)
                }
            }
            if let selected = selection, let country = catalog.country(id: selected.countryID) {
                let regions = catalog.subdivisions(countryID: country.id)
                if !regions.isEmpty {
                    TextField("Find a state or province", text: $regionQuery)
                    Picker(country.subdivisionsRequired ? "State / province (required)" : "State / province", selection: Binding(get: { selection?.subdivisionID ?? "" }, set: { value in
                        selection?.subdivisionID = value.isEmpty ? nil : value
                    })) {
                        Text("Choose a region").tag("")
                        ForEach(visibleRegions(countryID: country.id)) { region in
                            Text(region.aliases.first.map { "\($0) · \(region.name)" } ?? region.name).tag(region.id)
                        }
                    }
                }
                TextField("City or neighborhood (optional)", text: Binding(get: { selection?.locality ?? "" }, set: { value in
                    selection?.locality = value.isEmpty ? nil : String(value.prefix(200))
                }))
                Text(catalog.availabilityLabel(countryID: country.id, on: date)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var visibleCountries: [CountryPreset] {
        var values = catalog.searchableCountries(matching: query, on: date)
        if let id = selection?.countryID, !values.contains(where: { $0.id == id }), let current = catalog.country(id: id) { values.insert(current, at: 0) }
        return values
    }
    private func visibleRegions(countryID: String) -> [SubdivisionPreset] {
        var values = catalog.searchableSubdivisions(countryID: countryID, matching: regionQuery)
        if let id = selection?.subdivisionID, !values.contains(where: { $0.id == id }), let current = catalog.subdivision(id: id) {
            values.insert(current, at: 0)
        }
        return values
    }
}
