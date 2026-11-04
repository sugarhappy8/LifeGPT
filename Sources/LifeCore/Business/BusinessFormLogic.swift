import Foundation

extension BusinessSimulationState {
    /// The latest stored override values for exactly this jurisdiction; nil (a blank form) when it has none.
    public func currentFiscalOverrides(for ref: JurisdictionRef?) -> FiscalOverrides? {
        guard let ref else { return nil }
        return fiscalOverrides.last { $0.jurisdiction.countryID == ref.countryID && $0.jurisdiction.subdivisionID == ref.subdivisionID }?.values
    }
}

/// Pure form-to-request rules for the business manager so they can be tested without SwiftUI.
public enum BusinessFormLogic {
    /// Valid defaults for the "close account" pickers: neither may be the account being closed.
    public static func closeDefaults(accounts: [BankAccount], closing: String, preferred: String) -> (destination: String, replacement: String) {
        let others = accounts.filter { $0.id != closing }
        let personal = others.filter { $0.kind == .personal && $0.businessId == nil }
        return (others.first { $0.id == preferred }?.id ?? others.first?.id ?? "",
                personal.first { $0.id == preferred }?.id ?? personal.first?.id ?? "")
    }
    /// Birth date and contract hours apply only to payroll and owner salary; other kinds never carry or validate them.
    public static func contractDetails(kind: RecurringObligation.Kind, birthDate: String, hours: String) throws -> (birthDate: String?, monthlyHours: Int?) {
        guard kind == .payroll || kind == .ownerSalary else { return (nil, nil) }
        let hours = hours.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hours.isEmpty && Int(hours) == nil { throw ValidationError.invalid("Contract hours must be a whole number.") }
        let birth = birthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return (birth.isEmpty ? nil : birth, Int(hours))
    }
}
