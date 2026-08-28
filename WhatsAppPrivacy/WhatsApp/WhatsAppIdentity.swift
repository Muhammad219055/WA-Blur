enum WhatsAppIdentity {
    /// Verified against the installed app's Info.plist (2026-08-28).
    static let bundleIdentifier = "net.whatsapp.WhatsApp"

    /// Verified via `codesign -dv`. Documented for a possible future
    /// name+team-identifier fallback; not consulted by `matches` in Phase 1.
    /// A name-only fallback is deliberately not implemented: matching any
    /// app merely titled "WhatsApp" is a false-positive risk for a privacy
    /// tool (wrong window overlaid, or the real app left unprotected while a
    /// decoy matches first), and the bundle identifier is confirmed stable.
    static let teamIdentifier = "57T9237FN3"

    static func matches(_ app: RunningAppInfo) -> Bool {
        app.bundleIdentifier == bundleIdentifier
    }
}
