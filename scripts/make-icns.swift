import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("Usage: make-icns.swift <input.iconset> <output.icns>\n", stderr)
  exit(64)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

let entries: [(type: String, filename: String)] = [
  ("icp4", "icon_16x16.png"),
  ("icp5", "icon_32x32.png"),
  ("icp6", "icon_32x32@2x.png"),
  ("ic07", "icon_128x128.png"),
  ("ic08", "icon_256x256.png"),
  ("ic09", "icon_512x512.png"),
  ("ic10", "icon_512x512@2x.png"),
  ("ic11", "icon_16x16@2x.png"),
  ("ic12", "icon_32x32@2x.png"),
  ("ic13", "icon_128x128@2x.png"),
  ("ic14", "icon_256x256@2x.png")
]

func appendUInt32(_ value: UInt32, to data: inout Data) {
  var bigEndianValue = value.bigEndian
  withUnsafeBytes(of: &bigEndianValue) { bytes in
    data.append(contentsOf: bytes)
  }
}

var chunks = Data()

do {
  for entry in entries {
    guard let typeData = entry.type.data(using: .ascii), typeData.count == 4 else {
      throw NSError(domain: "ReloICNS", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Invalid ICNS type: \(entry.type)"
      ])
    }

    let imageURL = iconsetURL.appendingPathComponent(entry.filename)
    let imageData = try Data(contentsOf: imageURL)
    let chunkLength = UInt32(8 + imageData.count)

    chunks.append(typeData)
    appendUInt32(chunkLength, to: &chunks)
    chunks.append(imageData)
  }

  var icns = Data("icns".utf8)
  appendUInt32(UInt32(8 + chunks.count), to: &icns)
  icns.append(chunks)
  try icns.write(to: outputURL, options: .atomic)
} catch {
  fputs("Could not create ICNS: \(error)\n", stderr)
  exit(74)
}
