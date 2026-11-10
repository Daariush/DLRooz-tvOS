import Compression
import Foundation

/// Minimal ZIP reader for subtitle archives (SubDL / SubSource ship .zip files). Supports stored and
/// deflated entries, which is all subtitle sites produce.
enum ZipReader {
    struct Entry {
        let name: String
        let data: Data
    }

    static func isZip(_ data: Data) -> Bool { data.starts(with: [0x50, 0x4B, 0x03, 0x04]) }

    static func entries(_ data: Data) -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = findEOCD(bytes) else { return [] }
        let count = Int(u16(bytes, eocd + 10))
        var p = Int(u32(bytes, eocd + 16))
        var out: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014B50 else { break }
            let method = u16(bytes, p + 10)
            let compSize = Int(u32(bytes, p + 20))
            let size = Int(u32(bytes, p + 24))
            let nameLen = Int(u16(bytes, p + 28))
            let extraLen = Int(u16(bytes, p + 30))
            let commentLen = Int(u16(bytes, p + 32))
            let localOffset = Int(u32(bytes, p + 42))
            guard p + 46 + nameLen <= bytes.count else { break }
            let nameBytes = Data(bytes[(p + 46)..<(p + 46 + nameLen)])
            let name = String(data: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x04034B50 else { continue }
            let start = localOffset + 30 + Int(u16(bytes, localOffset + 26)) + Int(u16(bytes, localOffset + 28))
            guard start + compSize <= bytes.count, !name.hasSuffix("/") else { continue }
            let raw = Data(bytes[start..<(start + compSize)])
            switch method {
            case 0: out.append(Entry(name: name, data: raw))
            case 8: if let d = inflate(raw, size: size) { out.append(Entry(name: name, data: d)) }
            default: continue
            }
        }
        return out
    }

    /// Subtitle files in the archive, best match for `season`/`episode` first.
    static func subtitleFiles(_ data: Data, season: Int?, episode: Int?) -> [Entry] {
        let subs = entries(data).filter { e in
            let n = e.name.lowercased()
            return (n.hasSuffix(".srt") || n.hasSuffix(".vtt")) && !n.contains("__macosx")
        }
        guard let season, let episode else { return subs }
        let tags = [String(format: "s%02de%02d", season, episode), String(format: "%dx%02d", season, episode),
                    String(format: "e%02d", episode)]
        return subs.sorted { a, b in
            score(a.name.lowercased(), tags) > score(b.name.lowercased(), tags)
        }
    }

    private static func score(_ name: String, _ tags: [String]) -> Int {
        for (i, t) in tags.enumerated() where name.contains(t) { return tags.count - i }
        return 0
    }

    private static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), exactly what ZIP stores.
                return compression_decode_buffer(d, size, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written > 0 ? out.prefix(written) : nil
    }

    private static func findEOCD(_ b: [UInt8]) -> Int? {
        guard b.count >= 22 else { return nil }
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_535)
        while i >= stop {
            if u32(b, i) == 0x06054B50 { return i }
            i -= 1
        }
        return nil
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 1 < b.count else { return 0 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
