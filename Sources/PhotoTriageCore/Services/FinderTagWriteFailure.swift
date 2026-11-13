import Foundation

enum FinderTagWriteFailure {
    /// Only known permissions/read-only/metadata-support failures permit local
    /// fallback. A missing file or generic I/O error must remain an actual error.
    static func localFallbackReason(for error: Error) -> String? {
        var current = error as NSError
        for _ in 0..<5 {
            if current.domain == NSPOSIXErrorDomain {
                switch POSIXErrorCode(rawValue: Int32(current.code)) {
                case .EPERM, .EACCES:
                    return "文件或网络盘拒绝写入 Finder 标签；请检查文件权限及服务器元数据支持。"
                case .EROFS:
                    return "文件所在磁盘为只读，无法写入 Finder 标签。"
                case .ENOTSUP, .EOPNOTSUPP, .ENOSYS:
                    return "文件系统或网络盘不支持写入 Finder 标签。"
                default: break
                }
            }
            if current.domain == NSCocoaErrorDomain {
                if current.code == CocoaError.fileWriteNoPermission.rawValue {
                    return "没有权限写入 Finder 标签；请检查文件及共享目录的写入权限。"
                }
                if current.code == CocoaError.fileWriteVolumeReadOnly.rawValue {
                    return "文件所在磁盘为只读，无法写入 Finder 标签。"
                }
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return nil
    }
}
