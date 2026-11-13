import AppKit
import Foundation
import PhotoTriageCore

struct MacAssetInspectionService: AssetInspectionService {
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func quickLook(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}
