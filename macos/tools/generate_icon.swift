import Cocoa

let grid = [
    "................",
    "................",
    ".....XXXXXX.....",
    "....XXXXXXXX....",
    "....XXXXXXXX....",
    "....XXXXXXXX....",
    "....XXXXXXXX....",
    ".....XXXXXX.....",
    "......XXXX......",
    "......XXXX......",
    "......XXXX......",
    "......XXXX......",
    "......XXXX......",
    "....XXXXXXXX....",
    "................",
    "................"
]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: generate_icon.swift <iconset_dir> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}

let iconsetDir = args[1]
let icnsPath = args[2]

try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func render(size: Int) -> NSImage {
    let cell = size / 16
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    ctx.interpolationQuality = .none

    let radius = CGFloat(size) * 0.225
    let bgPath = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
        xRadius: radius,
        yRadius: radius
    )
    NSColor(srgbRed: 1.0, green: 0.55, blue: 0.0, alpha: 1.0).setFill()
    bgPath.fill()

    NSColor.white.setFill()
    for (row, line) in grid.enumerated() {
        for (col, ch) in line.enumerated() where ch == "X" {
            ctx.fill(CGRect(x: col * cell, y: row * cell, width: cell, height: cell))
        }
    }
    image.unlockFocus()
    return image
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in sizes {
    let img = render(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: iconsetDir).appendingPathComponent(name))
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
task.launch()
task.waitUntilExit()

if task.terminationStatus != 0 {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

print("Icon written to \(icnsPath)")
