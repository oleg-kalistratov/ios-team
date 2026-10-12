import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1])
let dst = URL(fileURLWithPath: args[2])
let uuid = args[3]
guard let s = CGImageSourceCreateWithURL(src as CFURL, nil),
      let d = CGImageDestinationCreateWithURL(dst as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { exit(1) }
let props: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["17": uuid]]
CGImageDestinationAddImageFromSource(d, s, 0, props as CFDictionary)
exit(CGImageDestinationFinalize(d) ? 0 : 2)
