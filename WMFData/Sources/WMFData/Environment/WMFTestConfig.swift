import Foundation

/// Debug-only launch configuration that lets a Maestro UI test point the app's networking at a
/// mock server (for example WireMock running on the host machine) instead of the production
/// Wikimedia backends.
///
/// Maestro launch arguments land in `UserDefaults.standard` (the `NSArgumentDomain`), and every
/// value arrives as a `String` regardless of its declared type — so boolean-ish values are parsed
/// from `"true"`/`"1"` here.
///
/// Everything is hard-gated behind `#if DEBUG`: in a release build the overrides always evaluate to
/// "no override" and the app's networking is completely untouched.
///
/// ## Launch arguments
/// - `apiBaseUrl` (String): full base URL of the mock, e.g. `http://localhost:8080`. The iOS
///   Simulator shares the host machine's network, so `localhost` reaches the host. When set, the
///   *scheme, host and port* of every API URL the app builds are rewritten to this value; the
///   request path and query are preserved. Canonical article URLs (`/wiki/Title`) are intentionally
///   left alone so the app can still derive language/identity from them.
/// - `disableCertPinning` (String `"true"`/`"1"`, or a Bool extra): the app does not pin
///   certificates, and its Info.plist already allows arbitrary/local loads, so this flag is
///   informational/parity only on iOS. It is parsed and exposed as ``certPinningDisabled``.
public enum WMFTestConfig {

    public static let apiBaseURLArgumentName = "apiBaseUrl"
    public static let disableCertPinningArgumentName = "disableCertPinning"

    /// The parsed `apiBaseUrl` override, or `nil` when it was not supplied / invalid / not a debug build.
    public static let apiBaseURLOverride: URL? = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: apiBaseURLArgumentName)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }
        return url
        #else
        return nil
        #endif
    }()

    /// Whether the test asked the app to disable certificate pinning. Informational on iOS (see above).
    public static let certPinningDisabled: Bool = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: disableCertPinningArgumentName)?
                .lowercased() else {
            return false
        }
        return raw == "true" || raw == "1"
        #else
        return false
        #endif
    }()

    public static var hasAPIBaseURLOverride: Bool {
        return apiBaseURLOverride != nil
    }

    /// Rewrites `components`' scheme/host/port to the mock server when an override is active,
    /// leaving the path and query untouched. A no-op when there is no override (and always in release).
    public static func applyAPIBaseURLOverride(to components: inout URLComponents) {
        guard let override = apiBaseURLOverride else {
            return
        }
        components.scheme = override.scheme
        components.host = override.host
        components.port = override.port
    }

    /// Convenience wrapper for call sites that hold an immutable `URLComponents`.
    public static func componentsApplyingAPIBaseURLOverride(_ components: URLComponents) -> URLComponents {
        var copy = components
        applyAPIBaseURLOverride(to: &copy)
        return copy
    }

    /// Call once at launch to surface the active override in the debug console. The override values
    /// themselves are read lazily from `UserDefaults`, so correctness does not depend on when (or
    /// whether) this is called.
    public static func applyLaunchOverrides() {
        #if DEBUG
        if let override = apiBaseURLOverride {
            print("[WMFTestConfig] apiBaseUrl override active → \(override.absoluteString) (certPinningDisabled=\(certPinningDisabled))")
        }
        #endif
    }
}
