import SwiftUI

/// Colour maths for the Window Border section: AeroSpace stores border colour as a
/// `0xAARRGGBB` string, which `ColorPicker` can't speak directly.
extension Color {
    /// Parses AeroSpace's `0xAARRGGBB` colour spelling. Returns `nil` for anything else,
    /// so the caller can fall back to a text field instead of mangling the value.
    init?(aeroSpaceHex hex: String) {
        let digits = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: Double((value >> 24) & 0xFF) / 255,
        )
    }

    var aeroSpaceHex: String {
        let components = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.white
        let byte = { (value: CGFloat) in UInt32((value * 255).rounded().clamped(to: 0 ... 255)) }
        let value = byte(components.alphaComponent) << 24
            | byte(components.redComponent) << 16
            | byte(components.greenComponent) << 8
            | byte(components.blueComponent)
        var hex = String(value, radix: 16)
        if hex.count < 8 { hex = String(repeating: "0", count: 8 - hex.count) + hex }
        return "0x" + hex
    }
}

extension CGFloat {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
