import Foundation

/// Stable preset identity; descriptive locality never changes the governing jurisdiction.
public struct JurisdictionRef: Codable, Hashable, Sendable {
    public var countryID: String
    public var subdivisionID: String?
    public var locality: String?
    private enum CodingKeys: String, CodingKey { case countryID = "countryId", subdivisionID = "subdivisionId", locality }
    public init(countryID: String, subdivisionID: String? = nil, locality: String? = nil) {
        self.countryID = countryID; self.subdivisionID = subdivisionID; self.locality = locality
    }
}

public struct CurrencyPeriod: Codable, Hashable, Sendable {
    public let code: String
    public let minorUnits: Int
    public let from: String
    public let until: String?
}

public struct CountryPreset: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let numericCode: String
    public let aliases: [String]
    public let currencyCode: String
    public let currencyMinorUnits: Int
    public let currencyPeriods: [CurrencyPeriod]
    public let validFrom: String?
    public let validUntil: String?
    public let predecessorIDs: [String]
    public let successorIDs: [String]
    public let subdivisionsRequired: Bool
    public let isHistorical: Bool
    public let annualPerCapitaScaleUSD: Double
    public let economicEvidence: String

    public func currency(on date: GameDate) -> CurrencyPeriod {
        let candidates = currencyPeriods.filter { $0.from <= date.iso && ($0.until == nil || $0.until! >= date.iso) }
        return candidates.sorted { $0.from > $1.from }.first
            ?? currencyPeriods.min { abs((GameDate(iso: $0.from) ?? date).daysSince(date)) < abs((GameDate(iso: $1.from) ?? date).daysSince(date)) }!
    }
    public func applies(on date: GameDate) -> Bool {
        (validFrom == nil || date.iso >= validFrom!) && (validUntil == nil || date.iso <= validUntil!)
    }
}

public struct SubdivisionPreset: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let countryID: String
    public let parentID: String
    public let name: String
    public let aliases: [String]
    public var displayName: String { countryID == "AE" ? (aliases.first ?? name) : name }
}

public struct CountryCatalog: Sendable {
    private struct Archive: Decodable {
        let version: String
        let referenceYear: Int
        let countries: [CountryPreset]
        let subdivisions: [SubdivisionPreset]
        let currencyUnitsPerUSD: [String: Double]
        let unobservedCurrencies: [String]
    }
    public static let shared: CountryCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Resources/Geography"),
              let data = try? Data(contentsOf: url), let archive = try? JSONDecoder().decode(Archive.self, from: data) else {
            preconditionFailure("The bundled nation catalog is missing or invalid.")
        }
        return CountryCatalog(archive: archive)
    }()
    public let version: String
    public let referenceYear: Int
    public let countries: [CountryPreset]
    public let allSubdivisions: [SubdivisionPreset]
    public let currencyUnitsPerUSD: [String: Double]
    public let unobservedCurrencies: Set<String>
    private let countriesByID: [String: CountryPreset]
    private let subdivisionsByID: [String: SubdivisionPreset]
    private init(archive: Archive) {
        version = archive.version; referenceYear = archive.referenceYear
        countries = archive.countries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        allSubdivisions = archive.subdivisions
        currencyUnitsPerUSD = archive.currencyUnitsPerUSD
        unobservedCurrencies = Set(archive.unobservedCurrencies)
        countriesByID = Dictionary(uniqueKeysWithValues: countries.map { ($0.id, $0) })
        subdivisionsByID = Dictionary(uniqueKeysWithValues: allSubdivisions.map { ($0.id, $0) })
    }
    public func country(id: String) -> CountryPreset? { countriesByID[id] }
    public func subdivision(id: String) -> SubdivisionPreset? { subdivisionsByID[id] }
    public func subdivisions(countryID: String) -> [SubdivisionPreset] {
        allSubdivisions.filter { $0.countryID == countryID }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Historical outside-range references remain available explicitly as estimates. Unknown IDs and cross-country regions never pass.
    public func validate(_ ref: JurisdictionRef, on date: GameDate, requireSubdivision: Bool = true) throws {
        guard let country = country(id: ref.countryID) else { throw ValidationError.invalid("Choose a nation from the preset catalog.") }
        guard (1...9999).contains(date.year), GameDate(iso: date.iso) != nil else { throw ValidationError.invalid("Choose a valid story date.") }
        if let region = ref.subdivisionID, subdivision(id: region)?.countryID != ref.countryID {
            throw ValidationError.invalid("Choose a region belonging to \(country.name).")
        }
        if requireSubdivision && country.subdivisionsRequired && ref.subdivisionID == nil {
            throw ValidationError.invalid("Choose a preset state or province for \(country.name).")
        }
        if let locality = ref.locality, locality.count > 200 { throw ValidationError.invalid("Locality must be at most 200 characters.") }
    }
    public func availabilityLabel(countryID: String, on date: GameDate) -> String {
        guard let country = country(id: countryID) else { return "Unknown nation" }
        if !country.applies(on: date) { return "Historical area estimate — preset boundaries/name do not apply on this date" }
        if country.isHistorical { return "Historical preset — local rules and subdivisions may be estimates" }
        if date.year < 1974 { return "Historical area estimate — earlier borders and local rules are not fully reconstructed" }
        if date.year > 2026 { return "Future projection — later rules are not yet sourced" }
        return "Preset nation — rule verification varies by factor and date"
    }
    public func displayName(_ ref: JurisdictionRef, on date: GameDate? = nil) -> String {
        guard let c = country(id: ref.countryID) else { return "Unresolved nation (\(ref.countryID))" }
        return [ref.locality?.trimmingCharacters(in: .whitespacesAndNewlines), ref.subdivisionID.flatMap { subdivision(id: $0)?.displayName }, c.name]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    public func searchableCountries(matching query: String, on date: GameDate) -> [CountryPreset] {
        let q = Self.normalized(query)
        return countries.filter { c in
            (q.isEmpty ? (!c.isHistorical || c.applies(on: date)) : ([c.name, c.id] + c.aliases).contains { Self.normalized($0).contains(q) })
        }
    }
    public func searchableSubdivisions(countryID: String, matching query: String) -> [SubdivisionPreset] {
        let q = Self.normalized(query)
        return subdivisions(countryID: countryID).filter { region in
            q.isEmpty || ([region.name, region.id] + region.aliases).contains { Self.normalized($0).contains(q) }
        }
    }
    /// Only exact, unambiguous names/aliases are mapped. Ambiguous city-only text remains unresolved.
    public func resolveLegacy(_ text: String, on date: GameDate) -> JurisdictionRef? {
        let parts = text.split(whereSeparator: { ",;\n".contains($0) }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalized = parts.map(Self.normalized)
        var matches = countries.filter { c in ([c.name, c.id] + c.aliases).map(Self.normalized).contains(where: normalized.contains) }
        if matches.count > 1 { let applicable = matches.filter { $0.applies(on: date) }; if applicable.count == 1 { matches = applicable } }
        guard matches.count == 1, let c = matches.first else { return nil }
        let regions = subdivisions(countryID: c.id).filter { r in ([r.name, r.id] + r.aliases).map(Self.normalized).contains(where: normalized.contains) }
        guard regions.count <= 1 else { return nil }
        let used = Set(([c.name, c.id] + c.aliases + regions.flatMap { [$0.name, $0.id] + $0.aliases }).map(Self.normalized))
        let locality = parts.filter { !used.contains(Self.normalized($0)) }.joined(separator: ", ")
        return JurisdictionRef(countryID: c.id, subdivisionID: regions.first?.id, locality: locality.isEmpty ? nil : locality)
    }
    public func economyAssumptions(for ref: JurisdictionRef, on date: GameDate) -> String {
        guard let country = country(id: ref.countryID) else { return "Unresolved nation; no country-specific prices are available." }
        let currency = country.currency(on: date)
        let conversionNote = unobservedCurrencies.contains(currency.code)
            ? " No conversion observation exists for \(currency.code); local wage/price scale uses an explicit neutral one-local-unit assumption, not asserted USD parity. Review these amounts."
            : " Currency conversion is a bundled scale estimate, not a historical market quote."
        return country.economicEvidence + conversionNote + " " + availabilityLabel(countryID: country.id, on: date)
    }
    public func economy(for ref: JurisdictionRef, on date: GameDate) throws -> EconomyCard {
        try validate(ref, on: date)
        let country = country(id: ref.countryID)!, currency = country.currency(on: date)
        let rate = currencyUnitsPerUSD[currency.code] ?? 1
        // Deliberately an economic estimate. This scales that area's own GDP/population, not US prices.
        let eraScale = pow(1.025, Double(max(-150, min(100, date.year - referenceYear))))
        let median = Int64(max(1, min(2.5e11, country.annualPerCapitaScaleUSD / 12 * 0.65 * rate * Double(currency.minorUnits) * eraScale)))
        return EconomyCard(currency: currency.code, minorUnitsPerUnit: currency.minorUnits,
            wageBands: [WageBand(name: "entry", minMonthlyMinor: max(1, median / 2), maxMonthlyMinor: median),
                        WageBand(name: "skilled", minMonthlyMinor: median, maxMonthlyMinor: median * 2),
                        WageBand(name: "professional", minMonthlyMinor: median * 2, maxMonthlyMinor: median * 4)],
            medianMonthlyIncomeMinor: median, monthlyLivingCostMinor: max(1, median * 55 / 100), version: 2)
    }
    /// Local dated prices expressed in the life's existing accounting currency, without reinterpreting balances.
    public func accountingEconomy(for ref: JurisdictionRef, on date: GameDate, accountingCurrency: String,
                                  minorUnitsPerUnit: Int, overrides: FiscalOverrides? = nil) throws -> EconomyCard {
        let local = try economy(for: ref, on: date)
        let fiscal = try FiscalRuleResolver.resolve(jurisdiction: ref, on: date, accountingCurrency: accountingCurrency,
            minorUnitsPerUnit: minorUnitsPerUnit, overrides: overrides)
        func convert(_ amount: Int64, positive: Bool = true) throws -> Int64 {
            let converted = try FiscalProfile.rounded(Decimal(amount) / Decimal(local.minorUnitsPerUnit)
                * Decimal(fiscal.conversion.accountingUnitsPerLocalUnit) * Decimal(minorUnitsPerUnit))
            return positive ? max(1, converted) : converted
        }
        let result = try EconomyCard(currency: accountingCurrency, minorUnitsPerUnit: minorUnitsPerUnit,
            wageBands: local.wageBands.map { WageBand(name: $0.name, minMonthlyMinor: try convert($0.minMonthlyMinor), maxMonthlyMinor: try convert($0.maxMonthlyMinor)) },
            medianMonthlyIncomeMinor: convert(local.medianMonthlyIncomeMinor), monthlyLivingCostMinor: convert(local.monthlyLivingCostMinor, positive: false), version: local.version)
        try result.validate()
        return result
    }
    private static func normalized(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).trimmingCharacters(in: .whitespacesAndNewlines) }
}
