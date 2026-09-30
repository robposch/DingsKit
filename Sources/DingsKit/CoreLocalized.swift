import Foundation

#if canImport(Darwin)
/// Loads a localized string from the `DingsKit` package bundle.
///
/// Resolves against `Bundle.module` so the package's `Localizable.xcstrings` is
/// used — the main bundle wouldn't contain it. Public so `DingsKitUI` views
/// (a separate target, so plain `internal` visibility would not reach them)
/// can localize their own copy against this same catalog instead of each app
/// having to re-host DingsKitUI's strings in its own bundle.
public func coreLocalized(_ value: String.LocalizationValue, comment: StaticString? = nil) -> String {
    String(localized: value, bundle: .module, comment: comment)
}
#else
/// Fallback for a non-Darwin Foundation, which has neither `String(localized:)`
/// nor catalog lookup: returns the English literal. DingsKit as a whole targets
/// Apple platforms and CI does not build this branch.
public func coreLocalized(_ value: String, comment: StaticString? = nil) -> String {
    value
}
#endif
