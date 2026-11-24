import Foundation
import Security

/// The app's version, build, commit, and code signature, for Settings, Debugging.
public struct BuildInfo: Sendable, Equatable {
    public var version: String
    public var build: String
    public var commit: String
    public var signing: String

    /// Reads the bundle's Info.plist and code signature. `scripts/bundle.sh` writes the commit
    /// into the `MeetingAgendaClockGitCommit` key.
    public static func current(bundle: Bundle = .main) -> BuildInfo {
        let info = bundle.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            commit: info["MeetingAgendaClockGitCommit"] as? String ?? "unknown",
            signing: signing(of: bundle.bundleURL))
    }

    static func signing(of url: URL) -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return describeSigning(isSigned: false, isAdHoc: false, teamID: nil)
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else {
            return describeSigning(isSigned: false, isAdHoc: false, teamID: nil)
        }
        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return describeSigning(
            isSigned: dictionary[kSecCodeInfoIdentifier as String] != nil,
            isAdHoc: flags & SecCodeSignatureFlags.adhoc.rawValue != 0,
            teamID: dictionary[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    /// How the app is signed, in words.
    public static func describeSigning(isSigned: Bool, isAdHoc: Bool, teamID: String?) -> String {
        if !isSigned { return "Not signed (a build run from the command line)" }
        if isAdHoc { return "Signed ad hoc" }
        if let teamID { return "Signed with a certificate from team \(teamID)" }
        return "Signed with a local certificate"
    }
}
