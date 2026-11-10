import Foundation

/// 直播源解析：兼容 m3u（#EXTINF + group-title）与 txt（"频道名,#genre#" 分组）两种格式
enum LiveParser {
    static func load(urlString: String) async throws -> [LiveGroup] {
        let data = try await Net.fetch(urlString)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !text.isEmpty else { throw NetError.decode }
        return parse(text: text)
    }

    static func parse(text: String) -> [LiveGroup] {
        if text.uppercased().contains("#EXTINF") {
            return parseM3U(text)
        }
        return parseTXT(text)
    }

    private static func parseTXT(_ text: String) -> [LiveGroup] {
        var groups: [LiveGroup] = []
        var currentGroupName = "默认"
        var currentChannels: [LiveChannel] = []

        func flush() {
            guard !currentChannels.isEmpty else { return }
            groups.append(LiveGroup(name: currentGroupName, channels: currentChannels))
            currentChannels = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmed()
            guard !line.isEmpty, !line.hasPrefix("//") else { continue }

            if line.contains("#genre#") {
                flush()
                let name = line.replacingOccurrences(of: ",#genre#", with: "")
                    .replacingOccurrences(of: "#genre#", with: "")
                    .trimmed()
                currentGroupName = name.isEmpty ? "默认" : name
                continue
            }

            let parts = line.components(separatedBy: ",")
            guard parts.count >= 2, let url = parts.last?.trimmed(), url.isHTTPURL else { continue }
            let name = parts.dropLast().joined(separator: ",").trimmed()
            currentChannels.append(LiveChannel(name: name.isEmpty ? url : name, url: url, group: currentGroupName))
        }
        flush()
        return groups
    }

    private static func parseM3U(_ text: String) -> [LiveGroup] {
        var order: [String] = []
        var buckets: [String: [LiveChannel]] = [:]
        var pendingName = ""
        var pendingGroup = "默认"

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmed()
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("#EXTINF") {
                pendingName = (line.components(separatedBy: ",").last ?? "").trimmed()
                pendingGroup = "默认"
                if let start = line.range(of: "group-title=\"") {
                    let rest = line[start.upperBound...]
                    if let end = rest.firstIndex(of: "\"") {
                        let value = String(rest[..<end]).trimmed()
                        if !value.isEmpty { pendingGroup = value }
                    }
                }
                continue
            }

            guard !line.hasPrefix("#"), line.isHTTPURL else { continue }

            let channel = LiveChannel(
                name: pendingName.isEmpty ? line : pendingName,
                url: line,
                group: pendingGroup
            )
            if buckets[pendingGroup] == nil {
                buckets[pendingGroup] = []
                order.append(pendingGroup)
            }
            buckets[pendingGroup]?.append(channel)
            pendingName = ""
        }

        return order.map { LiveGroup(name: $0, channels: buckets[$0] ?? []) }
    }
}
