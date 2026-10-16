/// A named cash account. Balances are derived from the immutable ledger.
public struct BankAccount: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case personal, business, savings, taxReserve = "tax_reserve", custom
    }
    public enum Status: String, Codable, Sendable { case active, closed, transferred }
    public enum Access: String, Codable, Sendable { case owner, manager, restricted, none }

    public var id: String
    public var name: String
    public var kind: Kind
    public var balanceMinor: Int64
    public var ownerId: String
    public var businessId: String?
    public var openedOn: GameDate?
    public var status: Status
    public var access: Access
    public var isAccessible: Bool { status == .active && (access == .owner || access == .manager) }

    public init(id: String, name: String, kind: Kind, balanceMinor: Int64 = 0,
                ownerId: String = "player", businessId: String? = nil, openedOn: GameDate? = nil,
                status: Status = .active, access: Access = .owner) {
        self.id = id
        self.name = name
        self.kind = kind
        self.balanceMinor = balanceMinor
        self.ownerId = ownerId; self.businessId = businessId; self.openedOn = openedOn
        self.status = status; self.access = access
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, balanceMinor, ownerId, businessId, openedOn, status, access
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        balanceMinor = try c.decodeIfPresent(Int64.self, forKey: .balanceMinor) ?? 0
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? "player"
        businessId = try c.decodeIfPresent(String.self, forKey: .businessId)
        openedOn = try c.decodeIfPresent(GameDate.self, forKey: .openedOn)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .active
        access = try c.decodeIfPresent(Access.self, forKey: .access) ?? .owner
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
