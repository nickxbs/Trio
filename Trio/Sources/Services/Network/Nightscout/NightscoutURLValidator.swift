import Foundation

enum NightscoutURLValidator {
    private static let allowedDomains: Set<String> = [
        "oracle.cgmsim.com",
        "oracle2.cgmsim.com"
    ]

    /// Checks if the provided URL conforms to https://<instance>.oracle.cgmsim.com or https://<instance>.oracle2.cgmsim.com
    static func isValidNightscoutURL(_ urlString: String) -> Bool {
        let cleaned = normalize(urlString)
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }

        // Path must be empty or root "/"
        if !url.path.isEmpty && url.path != "/" {
            return false
        }

        // Port must be empty or standard 443; no query parameters or fragments
        guard (url.port == nil || url.port == 443),
              url.query == nil,
              url.fragment == nil
        else {
            return false
        }

        let parts = host.split(separator: ".")
        // Must consist of <instance>.<domain> (exactly 4 components: instance + oracle/oracle2 + cgmsim + com)
        guard parts.count == 4 else { return false }

        let instance = String(parts[0])
        let domain = parts[1...].joined(separator: ".")

        guard allowedDomains.contains(domain) else { return false }

        // Instance subdomain characters: alphanumeric and hyphens, not empty, no hyphens at start/end
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard !instance.isEmpty,
              instance.unicodeScalars.allSatisfy({ allowedChars.contains($0) }),
              !instance.hasPrefix("-"),
              !instance.hasSuffix("-")
        else {
            return false
        }

        return true
    }

    /// Normalizes URL string: trims whitespace, auto-prepends https:// if missing, and removes trailing slashes
    static func normalize(_ urlString: String) -> String {
        var str = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.isEmpty, !str.lowercased().hasPrefix("http://"), !str.lowercased().hasPrefix("https://") {
            str = "https://" + str
        }
        while str.hasSuffix("/") {
            str = String(str.dropLast())
        }
        return str
    }

    static var validationErrorMessage: String {
        String(
            localized: "URL must be in the format https://<instance>.oracle.cgmsim.com or https://<instance>.oracle2.cgmsim.com",
            comment: "Nightscout URL domain restriction error"
        )
    }
}
