import Compression
import Foundation

/// Just enough of the ZIP format to take one file out of an archive: Garmin delivers an
/// activity's original file as a ZIP. Reads the central directory; entries are stored or
/// deflated (no ZIP64, encryption or multiple disks: Garmin's single-file archives have none).
enum Zip {
    enum ZipError: Error, Equatable {
        case notAZip
        case unsupported(method: Int)
        case corrupt
    }

    /// The contents of the first entry whose name ends in `.ext` (case-insensitive), or nil when
    /// there is none.
    static func firstFile(withExtension ext: String, in data: Data) throws -> Data? {
        let bytes = [UInt8](data)
        func u16(_ i: Int) throws -> Int {
            guard i >= 0, i + 2 <= bytes.count else { throw ZipError.corrupt }
            return Int(bytes[i]) | Int(bytes[i + 1]) << 8
        }
        func u32(_ i: Int) throws -> Int {
            guard i >= 0, i + 4 <= bytes.count else { throw ZipError.corrupt }
            return Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
        }

        // The end of central directory record: 22 bytes plus a comment of up to 64 KB, at the end.
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        var end = -1
        for i in stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65_535), by: -1)
        where bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 {
            end = i
            break
        }
        guard end >= 0 else { throw ZipError.notAZip }
        let entries = try u16(end + 10)
        var offset = try u32(end + 16)

        let suffix = "." + ext.lowercased()
        for _ in 0..<entries {
            guard try u32(offset) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = try u16(offset + 10)
            let compressedSize = try u32(offset + 20)
            let size = try u32(offset + 24)
            let nameLength = try u16(offset + 28), extraLength = try u16(offset + 30), commentLength = try u16(offset + 32)
            let local = try u32(offset + 42)
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.corrupt }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength
            guard name.lowercased().hasSuffix(suffix), !name.hasSuffix("/") else { continue }

            // The local header has its own name and extra field lengths.
            guard try u32(local) == 0x0403_4B50 else { throw ZipError.corrupt }
            let start = local + 30 + (try u16(local + 26)) + (try u16(local + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.corrupt }
            let stored = Data(bytes[start..<(start + compressedSize)])
            switch method {
            case 0: return stored
            case 8: return try inflate(stored, size: size)
            default: throw ZipError.unsupported(method: method)
            }
        }
        return nil
    }

    /// Raw DEFLATE (what ZIP stores; Apple's "zlib" algorithm is exactly that, without a header).
    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt }
        return output
    }
}
