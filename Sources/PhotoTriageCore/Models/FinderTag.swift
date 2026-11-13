import Foundation

public enum FinderTagColor: Int, CaseIterable, Codable, Hashable, Sendable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    public static let visibleColors: [FinderTagColor] = [
        .red, .orange, .yellow, .green, .blue, .purple, .gray,
    ]

    public var displayName: String {
        switch self {
        case .none: "无颜色"
        case .gray: "灰色"
        case .green: "绿色"
        case .purple: "紫色"
        case .blue: "蓝色"
        case .yellow: "黄色"
        case .red: "红色"
        case .orange: "橙色"
        }
    }
}

public struct FinderTag: Codable, Hashable, Identifiable, Sendable, ExpressibleByStringLiteral {
    public var name: String
    public var color: FinderTagColor

    public init(name: String, color: FinderTagColor = .none) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
    }

    public init(stringLiteral value: String) {
        self.init(encodedName: value)
    }

    public init(encodedName: String) {
        let components = encodedName.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let parsedName = String(components.first ?? "")
        let parsedColor = components.count == 2
            ? Int(components[1]).flatMap(FinderTagColor.init(rawValue:)) ?? .none
            : .none
        self.init(name: parsedName, color: parsedColor)
    }

    public var id: String { normalizedName }

    public var normalizedName: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    public var encodedName: String {
        color == .none ? name : "\(name)\n\(color.rawValue)"
    }

    public func matches(_ other: FinderTag) -> Bool {
        normalizedName == other.normalizedName
    }

    public static func normalized(_ tags: [FinderTag]) -> [FinderTag] {
        var result: [FinderTag] = []
        var indexesByName: [String: Int] = [:]

        for tag in tags where !tag.name.isEmpty {
            if let index = indexesByName[tag.normalizedName] {
                result[index] = tag
            } else {
                indexesByName[tag.normalizedName] = result.count
                result.append(tag)
            }
        }
        return result
    }
}

public enum FinderTagSelectionState: Sendable {
    case none
    case mixed
    case all
}
