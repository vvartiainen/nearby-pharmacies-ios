import SwiftUI
import UIKit

/// Colour, spacing and radius tokens from the design spec ("Tokens"). Each colour has a light and a
/// dark value and follows the current appearance.
extension Color {
  static let pageBackground = Color(light: 0xF2F4F6, dark: 0x0D141B)
  static let surfaceDefault = Color(light: 0xFFFFFF, dark: 0x17212B)
  static let borderSubtle = Color(light: 0xDCE1E6, dark: 0x2E3C49)
  static let borderStrong = Color(light: 0x8895A1, dark: 0x6B7A88)
  static let textPrimary = Color(light: 0x14202B, dark: 0xEEF2F5)
  static let textSecondary = Color(light: 0x51606E, dark: 0xA9B6C2)
  static let accentDefault = Color(light: 0x0B7A5A, dark: 0x3FBF8F)
  static let interactivePrimary = Color(light: 0x0B7A5A, dark: 0x3FBF8F)
  static let interactiveOnPrimary = Color(light: 0xFFFFFF, dark: 0x0D141B)
  static let pinSelected = Color(light: 0x06402F, dark: 0x8FE3C1)
  static let pinOutline = Color(light: 0xFFFFFF, dark: 0x0D141B)
  static let originMarker = Color(light: 0x1D5FBF, dark: 0x5B9BFF)
  static let selectionSurface = Color(light: 0xE3F2EC, dark: 0x163A2F)
  static let selectionBorder = Color(light: 0x06402F, dark: 0x8FE3C1)
  static let focusRing = Color(light: 0x1D5FBF, dark: 0x7FB0FF)
  static let noticeSurface = Color(light: 0xFFF4D6, dark: 0x3A2E10)
  static let noticeBorder = Color(light: 0xE2C06E, dark: 0x7A6230)
  static let noticeText = Color(light: 0x5C3D00, dark: 0xF5D48A)
  /// Result row distances below 500 m, below 1 km and from 1 km, as on web.
  static let distanceNear = Color(light: 0x166144, dark: 0x8FE3B1)
  static let distanceMedium = Color(light: 0x785300, dark: 0xF3CD76)
  static let distanceFar = Color(light: 0xA82B38, dark: 0xFF9DA0)
  /// The selection line between the origin and the selected pin, the same blue as the web app's.
  static let selectionLine = Color(light: 0x243E9E, dark: 0x5B9BFF)

  init(light: UInt32, dark: UInt32) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
      })
  }
}

extension UIColor {
  fileprivate convenience init(rgb: UInt32) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1
    )
  }
}

/// Spacing and radius in points.
enum Spacing {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 24
}

enum Radius {
  static let sm: CGFloat = 6
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
}

/// Minimum hit target from the design spec.
let minimumHitTarget: CGFloat = 44
