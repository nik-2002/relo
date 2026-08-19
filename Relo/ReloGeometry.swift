import CoreGraphics

/// Relo's macOS-style shape vocabulary.
///
/// Geometry follows role rather than forcing every component to use the same
/// radius: peer menu surfaces match, compact controls retain dense rounded
/// rectangles, independent floating surfaces can be softer, and prominent
/// pill-shaped controls derive their radius from their height.
enum ReloGeometry {
  static let menuSurfaceRadius: CGFloat = 14
  static let compactControlRadius: CGFloat = 6
  static let floatingSurfaceRadius: CGFloat = 15
  static let menuBarTimerRadius: CGFloat = 7

  static func capsuleRadius(forHeight height: CGFloat) -> CGFloat {
    max(0, height / 2)
  }
}
