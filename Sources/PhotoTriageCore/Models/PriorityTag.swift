import Foundation

/// Stable identity of a P label. Renaming its visible text never rewrites image decisions.
public struct PriorityTag: RawRepresentable, CaseIterable, Identifiable, Codable, Hashable, Comparable, Sendable {
    public let index: Int

    public init(index: Int) {
        precondition(index >= 0, "P label indices must be nonnegative")
        self.index = index
    }

    public init?(rawValue: String) {
        let value = rawValue.uppercased()
        guard value.first == "P", value.count > 1,
              value.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }),
              let index = Int(value.dropFirst()), index >= 0 else { return nil }
        self.index = index
    }

    public static let p0 = PriorityTag(index: 0)
    public static let p1 = PriorityTag(index: 1)
    public static let p2 = PriorityTag(index: 2)
    /// Built-in defaults only; use AppState.priorityTags for the user's complete catalog.
    public static let allCases: [PriorityTag] = [.p0, .p1, .p2]

    public var rawValue: String { "P\(index)" }
    public var id: String { rawValue }
    public var displayName: String { rawValue }
    public var appTag: AppTag { AppTag(name: rawValue) }

    public static func < (lhs: PriorityTag, rhs: PriorityTag) -> Bool { lhs.index < rhs.index }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let tag = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid P label identity")
        }
        self = tag
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func tag(forShortcut shortcut: String) -> PriorityTag? {
        let chord = shortcut.lowercased().replacingOccurrences(of: "⌘", with: "command+")
        guard chord.hasPrefix("command+"), let digit = Int(chord.dropFirst("command+".count)),
              (0...9).contains(digit) else { return nil }
        return PriorityTag(index: digit == 0 ? 9 : digit - 1)
    }

    public static func fromAppTag(_ tag: AppTag) -> PriorityTag? {
        Self(rawValue: tag.name)
    }
}

public struct PriorityTagDefinition: Codable, Equatable, Identifiable, Sendable {
    public let tag: PriorityTag
    public var name: String
    public var id: PriorityTag { tag }
    public var displayName: String { name }

    public init(tag: PriorityTag, name: String? = nil) {
        self.tag = tag
        self.name = name ?? tag.rawValue
    }

    public static let defaults = PriorityTag.allCases.map { PriorityTagDefinition(tag: $0) }
}

public enum PriorityTagCatalogError: Error, LocalizedError, Equatable {
    case emptyName
    case invalidName
    case duplicateName
    case reservedName
    case missingTag
    case tooManyTags

    public var errorDescription: String? {
        switch self {
        case .emptyName: "标签名称不能为空。"
        case .invalidName: "标签名称不能包含 /、\\、冒号或换行，且不能超过 80 个字符。"
        case .duplicateName: "已有同名标签，请换一个名称。"
        case .reservedName: "这个名称已被其他标签或导出分类使用，请换一个名称。"
        case .missingTag: "找不到这个 P 标签。"
        case .tooManyTags: "无法继续添加标签。"
        }
    }
}

public enum PriorityTagCatalog {
    public static func validatedName(_ proposed: String, for tag: PriorityTag, in definitions: [PriorityTagDefinition]) throws -> String {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw PriorityTagCatalogError.emptyName }
        guard name.count <= 80, name.utf8.count <= 240,
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil,
              name != ".", name != "..", !name.hasPrefix(".") else {
            throw PriorityTagCatalogError.invalidName
        }
        let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard !definitions.contains(where: { $0.tag != tag && $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) == key }) else {
            throw PriorityTagCatalogError.duplicateName
        }
        let reserved = ["keep", "reject", "pending", "保留", "淘汰", "未处理", "finder标签", "finder 标签"]
        guard !reserved.contains(key), PriorityTag(rawValue: name).map({ $0 == tag }) ?? true else {
            throw PriorityTagCatalogError.reservedName
        }
        return name
    }

    public static func normalized(_ definitions: [PriorityTagDefinition]) -> [PriorityTagDefinition] {
        var result = PriorityTagDefinition.defaults
        for definition in definitions.sorted(by: { $0.tag < $1.tag }) {
            guard let name = try? validatedName(definition.name, for: definition.tag, in: result) else { continue }
            if let index = result.firstIndex(where: { $0.tag == definition.tag }) {
                result[index].name = name
            } else {
                result.append(PriorityTagDefinition(tag: definition.tag, name: name))
            }
        }
        return result.sorted { $0.tag < $1.tag }
    }
}

public struct PriorityTagSummary: Equatable, Sendable {
    public var counts: [PriorityTag: Int]

    public init(p0Count: Int = 0, p1Count: Int = 0, p2Count: Int = 0) {
        counts = [:]
        if p0Count > 0 { counts[.p0] = p0Count }
        if p1Count > 0 { counts[.p1] = p1Count }
        if p2Count > 0 { counts[.p2] = p2Count }
    }

    public init(counts: [PriorityTag: Int]) { self.counts = counts.filter { $0.value > 0 } }

    public var p0Count: Int {
        get { count(for: .p0) }
        set { setCount(newValue, for: .p0) }
    }
    public var p1Count: Int {
        get { count(for: .p1) }
        set { setCount(newValue, for: .p1) }
    }
    public var p2Count: Int {
        get { count(for: .p2) }
        set { setCount(newValue, for: .p2) }
    }

    public var taggedCount: Int { counts.values.reduce(0, +) }
    public func count(for tag: PriorityTag) -> Int { counts[tag, default: 0] }
    public mutating func record(_ tag: PriorityTag?) {
        if let tag { counts[tag, default: 0] += 1 }
    }
    private mutating func setCount(_ count: Int, for tag: PriorityTag) {
        counts[tag] = count > 0 ? count : nil
    }

    public func ratio(for tag: PriorityTag) -> Double {
        guard taggedCount > 0 else { return 0 }
        return Double(count(for: tag)) / Double(taggedCount)
    }

    public func ratio(for tag: PriorityTag, totalCount: Int) -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(count(for: tag)) / Double(totalCount)
    }
}
