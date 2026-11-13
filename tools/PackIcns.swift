import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: swift PackIcns.swift <iconset> <output.icns>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: args[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: args[2])

let chunks: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

var body = Data()
for chunk in chunks {
    let fileURL = iconsetURL.appendingPathComponent(chunk.filename)
    let png = try Data(contentsOf: fileURL)
    appendFourCC(chunk.type, to: &body)
    appendUInt32(UInt32(png.count + 8), to: &body)
    body.append(png)
}

var output = Data()
appendFourCC("icns", to: &output)
appendUInt32(UInt32(body.count + 8), to: &output)
output.append(body)
try output.write(to: outputURL)

func appendFourCC(_ value: String, to data: inout Data) {
    precondition(value.utf8.count == 4)
    data.append(contentsOf: value.utf8)
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}
