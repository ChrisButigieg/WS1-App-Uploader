//
//  IPAInspector.swift
//  WS1 App Uploader
//
//  Pulls metadata out of an .ipa file.  An IPA is a zip archive that
//  contains `Payload/<AppName>.app/Info.plist`.
//
//  Foundation does not ship a public unzip API, so we reach for the
//  built-in libcompression — but only inspect the central directory.
//  For full extraction the user can fall back to providing an explicit
//  Info.plist via the "Use Info.plist" picker.
//

import Foundation
import Compression

struct IPAInspector {

    /// Attempt to locate and parse `Payload/.../Info.plist` inside an
    /// IPA.  Returns nil if the archive cannot be read with the
    /// minimal-zip strategy used here.  Every failure path emits a
    /// DebugLog entry so the operator can see why an IPA wasn't
    /// auto-parsed.
    static func metadata(for url: URL) -> AppPackageMetadata? {
        DebugLog.write("IPA inspect start — \(url.lastPathComponent)", level: .info)

        guard let archive = MinimalZip(url: url) else {
            DebugLog.write("IPA inspect: MinimalZip failed to open archive", level: .error)
            return nil
        }
        DebugLog.write("IPA inspect: archive opened — \(archive.entryCount) entries", level: .info)

        // Walk every candidate Info.plist and pick the one that lives
        // directly inside `Payload/<App>.app/`.  Some IPAs include
        // additional plists in PlugIns/, Frameworks/, or WatchKit
        // extensions — we want the top-level app's plist.
        let candidates = archive.entries(matching: { name in
            name.hasPrefix("Payload/")
                && name.contains(".app/")
                && name.hasSuffix("/Info.plist")
                && !name.contains("/Frameworks/")
                && !name.contains("/PlugIns/")
                && !name.contains(".appex/")
                && !name.contains(".framework/")
        })

        let topLevel = candidates.min(by: { $0.name.count < $1.name.count })
        guard let entry = topLevel else {
            DebugLog.write("IPA inspect: no Payload/*.app/Info.plist entry matched. First few names: \(archive.firstFewNames(10))", level: .error)
            return nil
        }
        DebugLog.write("IPA inspect: chose \(entry.name)  comp=\(entry.compressedSize) unc=\(entry.uncompressedSize) method=\(entry.compressionMethod)", level: .info)

        guard let data = archive.read(entry: entry) else {
            DebugLog.write("IPA inspect: failed to read \(entry.name)", level: .error)
            return nil
        }
        guard let parsed = InfoPlistExtractor.decode(data: data, sourceName: entry.name) else {
            DebugLog.write("IPA inspect: plist decode produced no metadata (data size=\(data.count))", level: .error)
            return nil
        }
        DebugLog.write("IPA inspect: parsed name=\(parsed.applicationName) bundle=\(parsed.bundleIdentifier) version=\(parsed.combinedVersion)", level: .info)
        return parsed
    }
}

// MARK: - Minimal Zip Reader

/// A read-only, just-enough zip parser for extracting one or two named
/// entries from an IPA.  Supports the deflate and store compression
/// methods, which together cover every IPA shipped by Xcode.
final class MinimalZip {

    struct Entry {
        let name: String
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let compressionMethod: UInt16
        /// File offset of the local file header.
        let localHeaderOffset: UInt64
    }

    private let handle: FileHandle
    private let totalSize: UInt64
    private let entries: [Entry]

    init?(url: URL) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = h
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        self.totalSize = UInt64((attrs[.size] as? NSNumber)?.intValue ?? 0)
        guard let parsed = Self.parseEntries(handle: h, totalSize: totalSize) else { return nil }
        self.entries = parsed
    }

    deinit { try? handle.close() }

    var entryCount: Int { entries.count }

    func firstEntry(matching predicate: (String) -> Bool) -> Entry? {
        entries.first(where: { predicate($0.name) })
    }

    func entries(matching predicate: (String) -> Bool) -> [Entry] {
        entries.filter { predicate($0.name) }
    }

    /// Sample of the first N entry names — used to log when the
    /// archive doesn't contain anything matching the IPA layout
    /// (probably not actually a zip, or unsupported variant).
    func firstFewNames(_ n: Int) -> String {
        entries.prefix(n).map(\.name).joined(separator: ", ")
    }

    func read(entry: Entry) -> Data? {
        do {
            try handle.seek(toOffset: entry.localHeaderOffset)
            // Local file header: 30 bytes fixed + name + extra
            guard let header = try handle.read(upToCount: 30), header.count == 30 else { return nil }
            // Signature must be 0x04034b50
            let sig = header.withUnsafeBytes { $0.load(as: UInt32.self) }
            guard sig.littleEndian == 0x04034b50 else { return nil }
            let nameLen  = header.readUInt16LE(at: 26)
            let extraLen = header.readUInt16LE(at: 28)
            try handle.seek(toOffset: entry.localHeaderOffset + 30 + UInt64(nameLen) + UInt64(extraLen))
            guard let raw = try handle.read(upToCount: Int(entry.compressedSize)) else { return nil }

            switch entry.compressionMethod {
            case 0: return raw
            case 8: return Self.inflate(raw, expectedSize: Int(entry.uncompressedSize))
            default: return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: - Parsing

    /// Walks the End-of-Central-Directory record back from the end of
    /// the file to enumerate every entry.
    private static func parseEntries(handle: FileHandle, totalSize: UInt64) -> [Entry]? {
        // Search the last 64 KiB for the EOCD signature 0x06054b50.
        let searchSize: UInt64 = min(totalSize, 65_557)
        let from = totalSize > searchSize ? totalSize - searchSize : 0
        do {
            try handle.seek(toOffset: from)
            let tail = try handle.read(upToCount: Int(searchSize)) ?? Data()

            guard let eocdRange = locateSignature(0x06054b50, in: tail) else { return nil }
            let eocdOffsetInFile = from + UInt64(eocdRange.lowerBound)
            // EOCD: 22 bytes fixed.  CD size & offset at +12, +16.
            let cdSize   = UInt64(tail.readUInt32LE(at: eocdRange.lowerBound + 12))
            let cdOffset = UInt64(tail.readUInt32LE(at: eocdRange.lowerBound + 16))
            let totalEntries = Int(tail.readUInt16LE(at: eocdRange.lowerBound + 10))
            _ = eocdOffsetInFile

            try handle.seek(toOffset: cdOffset)
            guard let cd = try handle.read(upToCount: Int(cdSize)) else { return nil }

            var entries: [Entry] = []
            var cursor = 0
            while cursor + 46 <= cd.count && entries.count < totalEntries {
                let signature = cd.readUInt32LE(at: cursor)
                guard signature == 0x02014b50 else { break }
                let method   = cd.readUInt16LE(at: cursor + 10)
                let compSize = UInt64(cd.readUInt32LE(at: cursor + 20))
                let uncSize  = UInt64(cd.readUInt32LE(at: cursor + 24))
                let nameLen  = Int(cd.readUInt16LE(at: cursor + 28))
                let extraLen = Int(cd.readUInt16LE(at: cursor + 30))
                let commLen  = Int(cd.readUInt16LE(at: cursor + 32))
                let localOff = UInt64(cd.readUInt32LE(at: cursor + 42))
                let nameStart = cursor + 46
                let nameEnd   = nameStart + nameLen
                guard nameEnd <= cd.count else { break }
                let name = String(data: cd.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? ""
                entries.append(Entry(name: name,
                                     compressedSize: compSize,
                                     uncompressedSize: uncSize,
                                     compressionMethod: method,
                                     localHeaderOffset: localOff))
                cursor = nameEnd + extraLen + commLen
            }
            return entries
        } catch {
            return nil
        }
    }

    private static func locateSignature(_ sig: UInt32, in data: Data) -> Range<Int>? {
        // Search backwards — EOCD is at end of archive.
        guard data.count >= 4 else { return nil }
        var i = data.count - 4
        while i >= 0 {
            if data.readUInt32LE(at: i) == sig {
                return i..<(i + 22)
            }
            i -= 1
        }
        return nil
    }

    /// Raw DEFLATE decompression using libcompression.  We allocate
    /// a destination buffer with headroom (`expectedSize` + 64 KiB)
    /// so the decoder can never error out on a borderline-sized
    /// destination, then trim the result to whatever it actually
    /// wrote.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        let bufferSize = max(expectedSize, 0) + 65_536
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        let written: Int = data.withUnsafeBytes { rawBuffer -> Int in
            guard let src = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(destination, bufferSize,
                                             src, data.count,
                                             nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else {
            DebugLog.write("Inflate failed — input=\(data.count) bytes, expected=\(expectedSize)", level: .error)
            return nil
        }
        return Data(bytes: destination, count: written)
    }
}

// MARK: - Data helpers

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        precondition(offset + 2 <= count, "out of range")
        let b0 = UInt16(self[self.startIndex + offset])
        let b1 = UInt16(self[self.startIndex + offset + 1])
        return b0 | (b1 << 8)
    }
    func readUInt32LE(at offset: Int) -> UInt32 {
        precondition(offset + 4 <= count, "out of range")
        let b0 = UInt32(self[self.startIndex + offset])
        let b1 = UInt32(self[self.startIndex + offset + 1])
        let b2 = UInt32(self[self.startIndex + offset + 2])
        let b3 = UInt32(self[self.startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
