// The client against a fake daemon on a Unix socket.

import Foundation
import Testing

@testable import CheeseclothKit

/// A daemon that reads one request line at a time and answers with the next
/// of `answers`, then closes the connection. It records the requests.
final class FakeDaemon: @unchecked Sendable {
    let path: String
    private let fd: Int32
    private let lock = NSLock()
    private var _requests: [String] = []

    var requests: [String] { lock.withLock { _requests } }

    init(answers: [String]) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("s").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        self.fd = fd
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8)
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            throw APIError.unreachable(String(cString: strerror(errno)))
        }
        Thread.detachNewThread { [self] in
            let conn = accept(fd, nil, nil)
            defer { close(conn) }
            var pending = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            for answer in answers {
                while !pending.contains(UInt8(ascii: "\n")) {
                    let n = read(conn, &buf, buf.count)
                    if n <= 0 { return }
                    pending.append(contentsOf: buf[0..<n])
                }
                let end = pending.firstIndex(of: UInt8(ascii: "\n"))!
                let line = String(decoding: pending[pending.startIndex..<end], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...end)
                lock.withLock { _requests.append(line) }
                let out = Array((answer + "\n").utf8)
                _ = out.withUnsafeBytes { write(conn, $0.baseAddress, $0.count) }
            }
        }
    }

    deinit {
        close(fd)
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }
}

let hello1 = #"{"ok":{"api":1,"daemon":"0.5.0"}}"#

@Test func aSessionSaysHelloFirstAndKeepsTheConnection() async throws {
    let config = try #require(try examples().first { $0.kind == "config" }?.json)
    let daemon = try FakeDaemon(answers: [hello1, #"{"ok":\#(config)}"#, #"{"ok":[]}"#])
    let (got, pending) = try await Client(socket: daemon.path).session { s -> (Config, [Proposal]) in
        (try s.send(.configGet), try s.send(.pending))
    }
    #expect(got.acceptors == 5)
    #expect(pending.isEmpty)
    #expect(daemon.requests == [#"{"cmd":"hello"}"#, #"{"cmd":"config_get"}"#, #"{"cmd":"pending"}"#])
}

@Test func aDaemonWithAnotherAPIVersionIsRefused() async throws {
    let daemon = try FakeDaemon(answers: [#"{"ok":{"api":2,"daemon":"9.0.0"}}"#])
    await #expect(throws: APIError.version(daemon: "9.0.0", api: 2)) {
        let _: Config = try await Client(socket: daemon.path).call(.configGet)
    }
}

@Test func aRefusedConnectionSaysWhoMay() async throws {
    let text = "only root and members of the group admin may use the cheesecloth daemon"
    let daemon = try FakeDaemon(answers: [#"{"err":"\#(text)"}"#])
    await #expect(throws: APIError.refused(text)) {
        let _: Config = try await Client(socket: daemon.path).call(.configGet)
    }
}

@Test func aMissingSocketIsUnreachable() async {
    await #expect {
        let _: Config = try await Client(socket: "/nonexistent/cheesecloth.sock").call(.configGet)
    } throws: { error in
        if case .unreachable = error as? APIError { true } else { false }
    }
}

@Test func aDaemonThatHangsUpIsAProtocolError() async throws {
    let daemon = try FakeDaemon(answers: [hello1])
    await #expect {
        let _: Config = try await Client(socket: daemon.path).call(.configGet)
    } throws: { error in
        error as? APIError == .protocolError("the daemon closed the connection")
    }
}
