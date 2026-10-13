// A connection to the daemon's local API: a Unix socket, one JSON line per
// request and per answer.

import Foundation

/// Why a request failed.
public enum APIError: Error, Equatable, CustomStringConvertible {
    /// No daemon listens on the socket, or the socket is missing.
    case unreachable(String)
    /// The daemon answered with a code and a message. Unknown codes are kept.
    case daemon(code: String, message: String)
    /// The daemon refused the connection: this user may not use it. The text
    /// says who may.
    case refused(String)
    /// The daemon serves another API version.
    case version(daemon: String, api: Int)
    /// A daemon from before error codes answered `hello` with a string error.
    case legacyVersion
    /// The connection broke, or the answer was not what LOCAL-API.md says.
    case protocolError(String)

    public var description: String {
        switch self {
        case let .unreachable(why): "Can't reach the cheesecloth daemon: \(why)"
        case let .daemon(_, message): message
        case let .refused(text): text
        case let .version(daemon, api):
            "The daemon (cheesecloth \(daemon)) speaks local API version \(api); this app speaks \(apiVersion)."
        case .legacyVersion: "The daemon is older than this app. Reinstall cheesecloth."
        case let .protocolError(why): "Unexpected answer from the daemon: \(why)"
        }
    }
}

/// Talks to the daemon at a socket path.
public struct Client: Sendable {
    public var socket: String

    /// The default socket of the daemon that the app runs.
    public static let defaultSocket = "/Library/Application Support/cheesecloth/control.sock"

    public init(socket: String = Client.defaultSocket) {
        self.socket = socket
    }

    /// Opens a connection, checks the API version with `hello`, and runs
    /// `body` with it. The blocking socket calls run off the caller's
    /// thread.
    public func session<T: Sendable>(
        _ body: @escaping @Sendable (Session) throws -> T
    ) async throws -> T {
        let socket = self.socket
        return try await Task.detached {
            let session = try Session(socket: socket)
            defer { session.close() }
            let hello: Hello = try session.send(.hello)
            guard hello.api == apiVersion else {
                throw APIError.version(daemon: hello.daemon, api: hello.api)
            }
            return try body(session)
        }.value
    }

    /// One request on its own connection.
    public func call<T: Decodable & Sendable>(_ request: Request) async throws -> T {
        try await session { try $0.send(request) }
    }
}

/// One open connection. Its calls block.
public final class Session: @unchecked Sendable {
    // Only one thread uses a session: the one `Client.session` runs on.
    private let fd: Int32
    private var buffer = Data()

    init(socket path: String) throws {
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw APIError.unreachable(Session.errno()) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw APIError.unreachable("the socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let why = Session.errno()
            Darwin.close(fd)
            throw APIError.unreachable("\(path): \(why)")
        }
        // A daemon that stops answering must not hang the app.
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
    }

    func close() {
        Darwin.close(fd)
    }

    /// Sends `request` and decodes the `ok` value of its answer.
    public func send<T: Decodable>(_ request: Request) throws -> T {
        var line = try request.line()
        line.append(UInt8(ascii: "\n"))
        try write(line)
        return try Session.decode(readLine())
    }

    /// Decodes one answer line: `{"ok": value}` or a coded error.
    static func decode<T: Decodable>(_ line: Data) throws -> T {
        let answer: Answer<T>
        do {
            answer = try decoder.decode(Answer<T>.self, from: line)
        } catch {
            throw APIError.protocolError(String(describing: error))
        }
        switch answer {
        case let .ok(value): return value
        case let .err(error):
            if error.code == "permission_denied" {
                throw APIError.refused(error.message)
            }
            throw APIError.daemon(code: error.code, message: error.message)
        case .legacyError: throw APIError.legacyVersion
        }
    }

    private func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if Darwin.errno == EINTR { continue }
                    if Darwin.errno == EPIPE {
                        throw APIError.protocolError("the daemon closed the connection")
                    }
                    throw APIError.protocolError("writing: \(Session.errno())")
                }
                offset += n
            }
        }
    }

    private func readLine() throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<end]
                buffer.removeSubrange(buffer.startIndex...end)
                return Data(line)
            }
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                if Darwin.errno == EINTR { continue }
                throw APIError.protocolError("reading: \(Session.errno())")
            }
            if n == 0 {
                throw APIError.protocolError("the daemon closed the connection")
            }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    private static func errno() -> String {
        String(cString: strerror(Darwin.errno))
    }
}

struct ErrorDocument: Decodable {
    let code: String
    let message: String
}

/// `{"ok": value}` or `{"err": {"code": ..., "message": ...}}`.
enum Answer<T: Decodable>: Decodable {
    case ok(T)
    case err(ErrorDocument)
    case legacyError

    private enum Keys: String, CodingKey { case ok, err }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if c.contains(.err) {
            if (try? c.decode(String.self, forKey: .err)) != nil {
                self = .legacyError
            } else {
                self = try .err(c.decode(ErrorDocument.self, forKey: .err))
            }
        } else if c.contains(.ok) {
            self = try .ok(c.decode(T.self, forKey: .ok))
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "neither ok nor err"))
        }
    }
}
