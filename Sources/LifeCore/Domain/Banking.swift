/// A named cash account. Balances are derived from the immutable ledger.
public struct BankAccount: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case personal, business, savings
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var balanceMinor: Int64

    public init(id: String, name: String, kind: Kind, balanceMinor: Int64 = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.balanceMinor = balanceMinor
    }
}

public struct AccountOpening: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: BankAccount.Kind

    public init(id: String, name: String, kind: BankAccount.Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct AccountTransfer: Codable, Equatable, Sendable {
    public var fromAccount: String
    public var toAccount: String
    public var amountMinor: Int64
    public var reason: String

    public init(fromAccount: String, toAccount: String, amountMinor: Int64, reason: String) {
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.amountMinor = amountMinor
        self.reason = reason
    }
}
