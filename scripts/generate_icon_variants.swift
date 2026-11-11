#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count == 5,
      let hue = Double(CommandLine.arguments[3]),
      let saturation = Double(CommandLine.arguments[4]) else {
    fputs("usage: generate_icon_variants.swift input.png output.png hue-radians saturation\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fputs("cannot decode input icon\n", stderr)
    exit(1)
}

let width = source.width, height = source.height, bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
    fputs("cannot create bitmap\n", stderr)
    exit(1)
}
context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

func shifted(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
    var h = 0.0
    if delta > 0 {
        if maximum == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maximum == g { h = (b - r) / delta + 2 }
        else { h = (r - g) / delta + 4 }
        h /= 6
        if h < 0 { h += 1 }
    }
    h = (h + hue / (2 * Double.pi)).truncatingRemainder(dividingBy: 1)
    if h < 0 { h += 1 }
    let s = maximum == 0 ? 0 : min(1, (delta / maximum) * saturation)
    let sector = h * 6, i = floor(sector), f = sector - i
    let p = maximum * (1 - s), q = maximum * (1 - s * f), t = maximum * (1 - s * (1 - f))
    switch Int(i) % 6 {
    case 0: return (maximum, t, p)
    case 1: return (q, maximum, p)
    case 2: return (p, maximum, t)
    case 3: return (p, q, maximum)
    case 4: return (t, p, maximum)
    default: return (maximum, p, q)
    }
}

for index in stride(from: 0, to: pixels.count, by: 4) {
    let result = shifted(Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255,
                         Double(pixels[index + 2]) / 255)
    pixels[index] = UInt8(max(0, min(255, Int(result.0 * 255 + 0.5))))
    pixels[index + 1] = UInt8(max(0, min(255, Int(result.1 * 255 + 0.5))))
    pixels[index + 2] = UInt8(max(0, min(255, Int(result.2 * 255 + 0.5))))
}

guard let rendered = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("cannot render icon\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("cannot write icon\n", stderr)
    exit(1)
}
