# Bundled geography and simulation profiles — 2026.10.17.1

The catalog contains all 249 currently assigned ISO 3166-1 countries and territories, 31 formerly assigned ISO 3166-3 identities, and 5,070 ISO 3166-2 subdivisions. ISO numeric identifiers align with UN M49 country/area identifiers. These presets are identifiers, not a position on territorial sovereignty.

## Redistributed data and attribution

- Names, identifiers, predecessor/successor relationships and subdivisions: https://github.com/wooorm/iso-3166 (`1.js`, `2.js`, `3.js`), fetched 2026-10-17. MIT license and copyright preserved in `ISO-DATA-LICENSE.txt`.
- Dated currency associations, denominations and territory population/GDP scale: Unicode CLDR 48, https://github.com/unicode-org/cldr-json (`cldr-core/supplemental/currencyData.json`, `territoryInfo.json`). Unicode License V3 preserved in `UNICODE-LICENSE.txt`.
- 2024 currency conversion observations: World Bank indicator PA.NUS.FCRF, https://api.worldbank.org/v2/country/all/indicator/PA.NUS.FCRF?format=json&date=2024&per_page=400 . Source attribution: World Bank, official exchange rate (LCU per US dollar, period average), sourced from IMF International Financial Statistics. World Bank datasets are distributed under CC BY 4.0 unless otherwise designated: https://datacatalog.worldbank.org/public-licenses#cc-by . Values are used as approximate scale anchors, never as historical market quotes.

## Authored assumptions

LifeGPT derives estimated median wages and living costs from each territory's GDP/population scale. GDP per person is **not** a measured median wage. The local estimate uses 65% of annual per-person output divided by 12, living costs at 55% of this wage estimate, and a bounded 2.5% annual era scale. Territories without an observation use an explicitly labeled neutral local simulation price scale. This is a game assumption, not sourced wage or cost-of-living data.

Historical preset applicability dates are a curated approximation to political/name changes and ISO withdrawals. Before a preset's supported interval, the UI explicitly calls it a historical area estimate. Current subdivision codes are not claimed to be a historical boundary map. Unobserved retired currencies use an explicitly labeled neutral conversion assumption; this is not an assertion of parity with USD.

Tax profiles distinguish sourced components, estimated assumptions and non-applicability for every supported factor. National/regional rates outside the reference components are estimates. References are embedded alongside the individual calculation factors. Historical US reference components cover FICA, federal bracket anchors and the federal wage floor (2003–2005); modeled payroll withholding, federal corporate provision, Texas franchise provision, unemployment, filing schedules and eligibility details remain estimates. UAE references cover ordinary mainland corporate threshold/rate and wage exclusion (2023–2026); pension applicability, remuneration, VAT eligibility, capital gains and special regimes remain explicit assumptions. This catalog does not claim complete legal verification for every nation or era.

Each calculation stores the profile version, story date, jurisdiction, accounting currency and conversion assumption. Catalog changes never rewrite previously recorded results.
