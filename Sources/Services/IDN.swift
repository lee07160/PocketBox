import Foundation

/// IDN 处理：把含中文等非 ASCII 字符的 URL 转成可正常解析的形式。
/// iOS 的 URL(string:) / URLComponents 对非 ASCII 域名会直接返回 nil，
/// 而这类中文域名接口在这个圈子里很常见（如 英格里希嗷呜.top、饭太硬.cc），必须自行转 punycode。
enum IDN {
    private static let base = 36
    private static let tmin = 1
    private static let tmax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN: Int = 128

    /// 归一化整个 URL：scheme 保持，域名逐段 punycode，路径/查询里的非 ASCII 做百分号编码
    static func normalize(_ raw: String) -> String? {
        let text = raw.trimmed()
        guard !text.isEmpty else { return nil }

        var scheme = ""
        var rest = text
        if let range = text.range(of: "://") {
            scheme = String(text[..<range.lowerBound]).lowercased()
            rest = String(text[range.upperBound...])
            // 只处理 http/https，其他 scheme 原样返回
            if scheme != "http" && scheme != "https" { return text }
        }

        // 域名部分：到第一个 / ? # 为止
        let hostPortion = String(rest.prefix { !"/?#".contains($0) })
        let remainder = String(rest.dropFirst(hostPortion.count))

        // 去掉 userinfo
        var host = hostPortion
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }

        let encodedHost: String
        if host.hasPrefix("[") {
            encodedHost = host // IPv6 字面量，原样保留
        } else if host.contains(where: { !$0.isASCII }) {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false).map { String($0) }
            encodedHost = labels.map { label in
                if label.isEmpty || label.allSatisfy({ $0.isASCII }) {
                    return label.lowercased()
                }
                return "xn--" + punycode(label)
            }.joined(separator: ".")
        } else {
            encodedHost = host.lowercased()
        }

        let prefix = scheme.isEmpty ? "" : scheme + "://"
        return prefix + encodedHost + percentEncodeNonASCII(remainder)
    }

    /// RFC 3492 Punycode 编码（已对拍 CPython 参考实现）
    static func punycode(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars).map { Int($0.value) }
        var output = scalars.filter { $0 < initialN }
        let basicCount = output.count

        var n = initialN
        var delta = 0
        var bias = initialBias
        var h = basicCount

        if basicCount > 0 { output.append(Int(UInt8(ascii: "-"))) }

        while h < scalars.count {
            guard let m = scalars.filter({ $0 >= n }).min() else { break }
            delta += (m - n) * (h + 1)
            n = m

            for c in scalars {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t: Int
                        if k <= bias { t = tmin }
                        else if k >= bias + tmax { t = tmax }
                        else { t = k - bias }
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta: delta, pointCount: h + 1, firstTime: h == basicCount)
                    delta = 0
                    h += 1
                }
            }

            delta += 1
            n += 1
        }

        return String(decoding: output.map { UInt32($0) }, as: Unicode.UTF32.self)
    }

    private static func digit(_ value: Int) -> Int {
        value < 26 ? Int(UInt8(ascii: "a")) + value : Int(UInt8(ascii: "0")) + value - 26
    }

    private static func adapt(delta: Int, pointCount: Int, firstTime: Bool) -> Int {
        var d = firstTime ? delta / damp : delta / 2
        d += d / pointCount
        var k = 0
        while d > ((base - tmin) * tmax) / 2 {
            d /= base - tmin
            k += base
        }
        return k + ((base - tmin + 1) * d) / (d + skew)
    }

    /// 路径/查询参数里的非 ASCII 字符做百分号编码，否则 URL(string:) 会失败
    private static func percentEncodeNonASCII(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            if byte < 0x80 {
                result.append(Character(Unicode.Scalar(byte)))
            } else {
                result.append(String(format: "%%%02X", byte))
            }
        }
        return result
    }
}
