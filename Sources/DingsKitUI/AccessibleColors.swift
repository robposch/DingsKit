import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Colors for *text* that carries meaning. The system's bright green, yellow
/// and orange are fine as icons and fills, but as text on a white background
/// they fall well short of the 4.5:1 contrast text needs. In Light Mode these
/// use darker shades; in Dark Mode the bright system colors already pass.
public enum AccessibleColors {
    /// Warnings and "attention" labels: demo data, beta, stale, Low Power Mode.
    public static var warning: Color { adaptive(light: (0.70, 0.33, 0.00), dark: .orange) }
    /// A good reading's word.
    public static var good: Color { adaptive(light: (0.11, 0.49, 0.18), dark: .green) }
    /// A fair reading's word.
    public static var fair: Color { adaptive(light: (0.55, 0.40, 0.00), dark: .yellow) }
    /// A poor reading's word.
    public static var poor: Color { adaptive(light: (0.77, 0.12, 0.12), dark: .red) }

    private static func adaptive(light: (Double, Double, Double), dark: Color) -> Color {
        #if canImport(UIKit) && !os(watchOS)
        let lightColor = UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        let darkColor = UIColor(dark)
        return Color(UIColor { traits in traits.userInterfaceStyle == .dark ? darkColor : lightColor })
        #else
        // watchOS is always dark.
        return dark
        #endif
    }
}
