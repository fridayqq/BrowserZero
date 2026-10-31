import Compression
import Foundation

/// Mozilla's LZ4 container: "mozLz40\0" magic, uint32 little-endian decompressed size, raw LZ4 block.
public enum MozLz4 {
    static let magic = Data("mozLz40\0".utf8)
    static let headerSize = 12

    public static func decode(_ data: Data) -> Data? {
        guard data.count > headerSize, data.prefix(magic.count) == magic else { return nil }
        let bytes = [UInt8](data)
        let size = (0..<4).reduce(0) { $0 | Int(bytes[8 + $1]) << (8 * $1) }
        guard size > 0 else { return nil }
        let source = Array(bytes[headerSize...])

        var output = [UInt8](repeating: 0, count: size)
        let written = compression_decode_buffer(
            &output, size, source, source.count, nil, COMPRESSION_LZ4_RAW
        )
        return written == size ? Data(output) : nil
    }

    public static func encode(_ data: Data) -> Data {
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: source.count + 1024)
        let written = compression_encode_buffer(
            &destination, destination.count, source, source.count, nil, COMPRESSION_LZ4_RAW
        )
        var header = magic
        header.append(contentsOf: (0..<4).map { UInt8((source.count >> (8 * $0)) & 0xFF) })
        return header + Data(destination.prefix(written))
    }
}
