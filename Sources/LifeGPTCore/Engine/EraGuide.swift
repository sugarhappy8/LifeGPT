import Foundation

/// Short, decade-level anchors that keep the AI's events plausible for the time period.
/// The model knows history well; these lines mostly remind it to *apply* that knowledge
/// (prices, technology, norms) instead of drifting into the present day.
public enum EraGuide {
    public static func notes(for year: Int) -> String {
        let decade = (year / 10) * 10
        let anchor: String
        switch decade {
        case ..<1900: anchor = "Pre-1900: no cars, telephones are rare, most people farm or do manual trades, medicine is primitive and childhood mortality is high."
        case 1900: anchor = "1900s: horse transport giving way to early automobiles, telegraph and early telephones, factory work, few labor protections."
        case 1910: anchor = "1910s: World War I (1914-1918) and the 1918 influenza pandemic dominate; conscription, rationing, silent films."
        case 1920: anchor = "1920s: postwar boom, radio, jazz, Prohibition in the US, cars for the middle class; ends with the 1929 crash."
        case 1930: anchor = "1930s: the Great Depression, mass unemployment, breadlines, the Dust Bowl, rising fascism in Europe."
        case 1940: anchor = "1940s: World War II (1939-1945), rationing, war work, then demobilization, the GI Bill and the start of the Cold War."
        case 1950: anchor = "1950s: postwar prosperity, suburbs, television arrives, rock and roll, the Korean War, civil rights struggle begins."
        case 1960: anchor = "1960s: civil rights movement, Vietnam War and the draft, counterculture, the space race and the Moon landing."
        case 1970: anchor = "1970s: oil shocks, stagflation, Watergate, disco and punk, early personal computers appear late in the decade."
        case 1980: anchor = "1980s: Reagan/Thatcher era, home computers and video games, MTV, the AIDS crisis, Cold War ends with the Berlin Wall in 1989."
        case 1990: anchor = "1990s: the internet and mobile phones spread, dot-com boom, grunge and hip-hop, relative peace and prosperity in the West."
        case 2000: anchor = "2000s: 9/11 and the wars that followed, social media and smartphones arrive, the 2008 financial crisis."
        case 2010: anchor = "2010s: smartphones everywhere, the gig economy, streaming, student debt, political polarization."
        case 2020: anchor = "2020s: the COVID-19 pandemic, remote work, inflation, generative AI goes mainstream."
        default: anchor = "\(decade)s: the future. Extrapolate plausibly from today's technology and society; keep it grounded."
        }
        return anchor
    }
}
