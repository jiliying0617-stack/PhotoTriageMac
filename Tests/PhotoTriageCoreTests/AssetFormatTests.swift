import Foundation
import PhotoTriageCore
import Testing

struct AssetFormatTests {
    @Test
    func inferRecognizesSupportedExtensionsCaseInsensitively() {
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.JPG")) == .jpg)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.jpeg")) == .jpg)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.HeIc")) == .heic)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.WEBP")) == .webp)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.CR2")) == .cr2)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.arw")) == .arw)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.DNG")) == .dng)
    }

    @Test
    func inferReturnsUnknownForUnsupportedExtensions() {
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a.txt")) == .unknown)
        #expect(AssetFormat.infer(from: URL(fileURLWithPath: "/tmp/a")) == .unknown)
    }
}
