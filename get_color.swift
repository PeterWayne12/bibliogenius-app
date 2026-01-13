import CoreGraphics
import ImageIO
import Foundation

// Use the 1024 icon for source
let inputPath = "assets/images/app_background.png" // This is the old cropped one, might allow reading color. 
// detailed: actually let's use the icon we have: play_store_icon_512.png
let iconPath = "play_store_icon_512.png"

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: iconPath) as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("Failed to load image")
    exit(1)
}

// Get pixel data from top-left (0,0)
let data = cgImage.dataProvider?.data
let ptr = CFDataGetBytePtr(data)
// Assuming RGBA or RGB.
// We'll just dump the first few bytes.
// Actually, let's just make a new script that CREATES the image using a hardcoded nice Teal if we can't easily parse.
// But getting the color is better.

// Create a 1x1 context to draw the (0,0) pixel into and get RGBA
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
var pixel = [UInt8](repeating: 0, count: 4)
let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo)!

// Draw the image such that 0,0 is drawn to our 1x1 context
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
// This draws the whole image into 1x1? No.
// We want to sample. 
// Let's just draw the WHOLE image into a 1x1 context? NO.
// Let's draw the image offset so 0,0 lands on 0,0?
// context.translateBy(x: 0, y: 0) // default
// context.draw(...) scales it if rect is different?
// Let's just clip?

// Simpler: Just rely on "Deep Teal" hex code if we know it.
// The user said "uniform background".
// Let's print the r,g,b values.

print("R: \(pixel[0]) G: \(pixel[1]) B: \(pixel[2])")
