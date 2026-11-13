import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct FileSystemFinderTagService: FinderTagSyncing {
    private static let userTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    public init() {}

    public func readTags(at url: URL) throws -> [FinderTag] {
        #if canImport(Darwin)
        guard let data = try extendedAttributeData(at: url) else {
            return []
        }
        if let encodedNames = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
            return FinderTag.normalized(encodedNames.map(FinderTag.init(encodedName:)))
        }
        #endif

        let values = try url.resourceValues(forKeys: [.tagNamesKey])
        return FinderTag.normalized((values.tagNames ?? []).map(FinderTag.init(encodedName:)))
    }

    public func writeTags(_ tags: [FinderTag], at url: URL) throws {
        let encodedNames = FinderTag.normalized(tags).map(\.encodedName)
        #if canImport(Darwin)
        try writeExtendedAttribute(encodedNames, at: url)
        #else
        try (url as NSURL).setResourceValue(encodedNames, forKey: .tagNamesKey)
        #endif
    }

    #if canImport(Darwin)
    private func extendedAttributeData(at url: URL) throws -> Data? {
        try url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, Self.userTagsAttribute, nil, 0, 0, 0)
            if size < 0 {
                if errno == ENOATTR { return nil }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard size > 0 else { return nil }

            var data = Data(count: size)
            let bytesRead = data.withUnsafeMutableBytes { buffer in
                getxattr(path, Self.userTagsAttribute, buffer.baseAddress, size, 0, 0)
            }
            guard bytesRead >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if bytesRead < data.count {
                data.removeSubrange(bytesRead..<data.count)
            }
            return data
        }
    }

    private func writeExtendedAttribute(_ encodedNames: [String], at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }

            if encodedNames.isEmpty {
                if removexattr(path, Self.userTagsAttribute, 0) < 0, errno != ENOATTR {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                return
            }

            let data = try PropertyListSerialization.data(
                fromPropertyList: encodedNames,
                format: .binary,
                options: 0
            )
            let result = data.withUnsafeBytes { buffer in
                setxattr(path, Self.userTagsAttribute, buffer.baseAddress, data.count, 0, 0)
            }
            if result < 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
    #endif
}
