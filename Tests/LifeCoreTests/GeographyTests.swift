import Foundation
import Testing
@testable import LifeCore

@Suite("Nation presets and dated geography")
struct GeographyTests {
    let catalog = CountryCatalog.shared
    let date = GameDate(year: 2024, month: 6, day: 1)

    @Test func completeCatalogHasStableUniqueIDsAndRegionalParents() throws {
        #expect(catalog.countries.filter { !$0.isHistorical }.count == 249)
        #expect(catalog.countries.filter(\.isHistorical).count == 31)
        #expect(Set(catalog.countries.map(\.id)).count == catalog.countries.count)
        #expect(catalog.allSubdivisions.count > 5_000)
        #expect(Set(catalog.allSubdivisions.map(\.id)).count == catalog.allSubdivisions.count)
        for country in catalog.countries {
            #expect(!country.currencyPeriods.isEmpty)
            #expect(country.currencyPeriods.allSatisfy { $0.minorUnits > 0 })
            if country.subdivisionsRequired { #expect(!catalog.subdivisions(countryID: country.id).isEmpty) }
        }
        for region in catalog.allSubdivisions { #expect(catalog.country(id: region.countryID) != nil) }
    }
    @Test func regionSearchFindsUnaccentedNamesAndKeepsCountryScope() {
        #expect(catalog.searchableSubdivisions(countryID: "JP", matching: " tokyo ").map(\.id) == ["JP-13"])
        #expect(catalog.searchableSubdivisions(countryID: "JP", matching: "JP-13").map(\.id) == ["JP-13"])
        #expect(catalog.searchableSubdivisions(countryID: "US", matching: "Tokyo").isEmpty)
    }

    @Test func rejectsUnknownNationsAndForeignRegions() throws {
        #expect(throws: (any Error).self) { try catalog.validate(JurisdictionRef(countryID: "Atlantis"), on: date) }
        #expect(throws: (any Error).self) { try catalog.validate(JurisdictionRef(countryID: "AE", subdivisionID: "US-TX"), on: date) }
        #expect(throws: (any Error).self) { try catalog.validate(JurisdictionRef(countryID: "US"), on: date) }
        try catalog.validate(JurisdictionRef(countryID: "US", subdivisionID: "US-TX", locality: "Plano"), on: date)
    }
    @Test func legacyResolutionUsesNamesAndPreservesUnresolvedText() {
        let texas = catalog.resolveLegacy("texas, USA", on: date)
        #expect(texas == JurisdictionRef(countryID: "US", subdivisionID: "US-TX"))
        #expect(catalog.resolveLegacy("Dubai, UAE", on: date)?.countryID == "AE")
        #expect(catalog.resolveLegacy("Abu Dhabi, UAE", on: date)?.subdivisionID == "AE-AZ")
        #expect(catalog.resolveLegacy("a town near the beach", on: date) == nil)
        #expect(catalog.resolveLegacy("France, Germany", on: date) == nil)
        #expect(catalog.resolveLegacy("Paris", on: date) == nil)
    }
    @Test func historicalPresetsAndOutOfRangeLabelsAreExplicit() throws {
        let soviet = try #require(catalog.country(id: "SUHH"))
        #expect(soviet.applies(on: GameDate(year: 1980, month: 1, day: 1)))
        #expect(!soviet.applies(on: date))
        #expect(soviet.successorIDs.contains("RU"))
        #expect(catalog.availabilityLabel(countryID: "SUHH", on: date).contains("boundaries/name do not apply"))
        #expect(catalog.availabilityLabel(countryID: "AE", on: GameDate(year: 1850, month: 1, day: 1)).contains("Historical"))
        #expect(catalog.availabilityLabel(countryID: "FR", on: GameDate(year: 2100, month: 1, day: 1)).contains("Future"))
        #expect(catalog.searchableCountries(matching: "Soviet", on: date).contains { $0.id == "SUHH" })
    }
    @Test func currencyFollowsTheStoryDateAndDenomination() throws {
        let france = try #require(catalog.country(id: "FR"))
        #expect(france.currency(on: GameDate(year: 1990, month: 1, day: 1)).code == "FRF")
        #expect(france.currency(on: date).code == "EUR")
        #expect(catalog.country(id: "JP")?.currency(on: date).minorUnits == 1)
        #expect(catalog.country(id: "KW")?.currency(on: date).minorUnits == 1000)
    }
    @Test func manualEconomiesNeverFallBackToUSPrices() throws {
        let japan = try catalog.economy(for: JurisdictionRef(countryID: "JP", subdivisionID: "JP-13"), on: date)
        let india = try catalog.economy(for: JurisdictionRef(countryID: "IN", subdivisionID: "IN-MH"), on: date)
        let uae = try catalog.economy(for: JurisdictionRef(countryID: "AE", subdivisionID: "AE-DU"), on: date)
        #expect(japan.currency == "JPY" && japan.minorUnitsPerUnit == 1)
        #expect(india.currency == "INR")
        #expect(uae.currency == "AED")
        #expect(japan != .sampleUS2005 && india != .sampleUS2005 && uae != .sampleUS2005)
        #expect(japan.medianMonthlyIncomeMinor != india.medianMonthlyIncomeMinor)
        for c in catalog.countries {
            let ref = JurisdictionRef(countryID: c.id, subdivisionID: c.subdivisionsRequired ? catalog.subdivisions(countryID: c.id).first?.id : nil)
            let economy = try catalog.economy(for: ref, on: date)
            try economy.validate()
        }
    }
    @Test func relocationConvertsTheLocalEconomyWithoutChangingAccountingCurrency() throws {
        let japan = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo")
        let native = try catalog.economy(for: japan, on: date)
        let dollars = try catalog.accountingEconomy(for: japan, on: date, accountingCurrency: "USD", minorUnitsPerUnit: 100)
        #expect(native.currency == "JPY" && dollars.currency == "USD")
        #expect(dollars.minorUnitsPerUnit == 100)
        let rate = try FiscalRuleResolver.resolve(jurisdiction: japan, on: date, accountingCurrency: "USD", minorUnitsPerUnit: 100).conversion.accountingUnitsPerLocalUnit
        let expected = Int64((Double(native.medianMonthlyIncomeMinor) * rate * 100).rounded())
        #expect(abs(dollars.medianMonthlyIncomeMinor - expected) <= 1)
        #expect(dollars != .sampleUS2005)
        let overridden = try catalog.accountingEconomy(for: japan, on: date, accountingCurrency: "USD", minorUnitsPerUnit: 100,
            overrides: FiscalOverrides(accountingUnitsPerLocalUnit: 0.01))
        #expect(overridden.medianMonthlyIncomeMinor == native.medianMonthlyIncomeMinor)
    }
    @Test func setupSeparatesBirthplaceFromStartingResidenceAndUsesLocalEconomy() throws {
        var character = TestChat.newCharacter(age: 18)
        character.birthplace = "Plano, Texas, USA"
        character.birthJurisdiction = JurisdictionRef(countryID: "US", subdivisionID: "US-TX", locality: "Plano")
        character.startingJurisdiction = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo")
        let draft = SetupDraft.manual(for: character)
        #expect(draft.economy.currency == "JPY")
        #expect(draft.economy.minorUnitsPerUnit == 1)
        #expect(draft.opening.contains("Japan"))
        #expect(draft.lifeState.first { $0.key == "residence" }?.value == CountryCatalog.shared.displayName(character.startingJurisdiction!))
        let store = try TestChat.library().createChat(character: character, setup: draft, settings: SessionSettings()).store
        #expect(try store.character().birthplace == character.birthplace)
        #expect(try store.placeTimeBriefs().last?.location == CountryCatalog.shared.displayName(character.startingJurisdiction!))
    }
    @Test func generatedSetupRetainsSelectedCurrencyAndCanonicalResidence() async throws {
        var character = TestChat.newCharacter(age: 18)
        character.birthJurisdiction = JurisdictionRef(countryID: "US", subdivisionID: "US-TX")
        character.startingJurisdiction = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo")
        let correct = SetupDraft.manual(for: character)
        var wrong = correct; wrong.economy = .sampleUS2005
        let provider = StubProvider(responses: [StubProvider.reply(String(decoding: try JSONEncoder().encode(wrong), as: UTF8.self)),
            StubProvider.reply(String(decoding: try JSONEncoder().encode(correct), as: UTF8.self))])
        let result = try await SetupGenerator(provider: provider).generate(character)
        #expect(provider.requests.count == 2)
        #expect(result.economy.currency == "JPY")
        #expect(provider.requests[0].user.contains("Japan [JP]"))
    }
    @Test func locationIdentityRoundTripsWithoutLosingOriginalLocality() throws {
        let value = JurisdictionRef(countryID: "US", subdivisionID: "US-TX", locality: "Plano, north side")
        #expect(try JSONDecoder().decode(JurisdictionRef.self, from: JSONEncoder().encode(value)) == value)
        let wire = try OutputCoding.encoder.encode(value)
        #expect(String(decoding: wire, as: UTF8.self).contains("country_id"))
        #expect(try OutputCoding.decoder.decode(JurisdictionRef.self, from: wire) == value)
        let manualWire = Data(#"{"country_id":"US","subdivision_id":"US-TX","locality":"Plano"}"#.utf8)
        #expect(try OutputCoding.decoder.decode(JurisdictionRef.self, from: manualWire).subdivisionID == "US-TX")
        #expect(catalog.displayName(value).contains("Plano, north side"))
        #expect(catalog.displayName(value).contains("Texas"))
    }
}
