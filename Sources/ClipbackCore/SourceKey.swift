import Foundation

/// Groups clips that came from the same page or file, so everything clipped from one article is in one place.
public enum SourceKey {
    /// Pages compare by host, path and meaningful query (tracking parameters and #fragments ignored);
    /// files by path. Clips with only an app and window have no key.
    public static func key(for source: ClipSource) -> String? {
        if let raw = source.url, var components = URLComponents(string: raw), let host = components.host {
            components.fragment = nil
            components.scheme = components.scheme?.lowercased()
            components.host = host.lowercased().replacingOccurrences(of: "www.", with: "")
            let kept = (components.queryItems ?? []).filter { !isTracking($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept.sorted { $0.name < $1.name }
            if components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
            return components.string.map { "url:" + $0 }
        }
        if let file = source.file {
            return "file:" + file
        }
        return nil
    }

    private static func isTracking(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("utm_") || ["fbclid", "gclid", "ref", "ref_src", "si", "mc_cid", "mc_eid"].contains(lowered)
    }
}
