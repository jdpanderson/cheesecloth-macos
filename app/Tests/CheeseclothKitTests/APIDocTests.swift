// The app's API types against the examples in cheesecloth's
// docs/LOCAL-API.md: each example decodes, and writes back as the same JSON.

import Foundation
import Testing

@testable import CheeseclothKit

/// LOCAL-API.md from `CHEESECLOTH_API_DOC`, or from a cheesecloth checkout
/// beside this one (see cheesecloth's docs/REPOSITORIES.md). CI checks out
/// the pinned commit or tag and sets the variable.
func apiDoc() throws -> String {
    let path =
        ProcessInfo.processInfo.environment["CHEESECLOTH_API_DOC"]
        ?? URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // .../app/Tests/CheeseclothKitTests
        .deletingLastPathComponent()  // .../app/Tests
        .deletingLastPathComponent()  // .../cheesecloth-macos/app
        .deletingLastPathComponent()  // .../cheesecloth-macos
        .deletingLastPathComponent()  // the folder of both checkouts
        .appendingPathComponent("cheesecloth/docs/LOCAL-API.md").path
    return try String(contentsOfFile: path, encoding: .utf8)
}

/// The JSON examples, each with the word after "json" on its fence.
func examples() throws -> [(kind: String, json: String)] {
    var out: [(String, String)] = []
    var lines = try apiDoc().components(separatedBy: "\n")[...]
    while let line = lines.popFirst() {
        guard line.hasPrefix("```json ") else { continue }
        let kind = String(line.dropFirst("```json ".count))
        var body: [String] = []
        while let l = lines.popFirst(), l != "```" { body.append(l) }
        out.append((kind, body.joined(separator: "\n")))
    }
    return out
}

/// JSON as plain values, with nulls dropped: Swift leaves out a nil field
/// where the daemon writes null, and both mean the same.
func plain(_ data: Data) throws -> NSObject {
    func strip(_ v: Any) -> Any {
        if let d = v as? [String: Any] {
            return d.filter { !($0.value is NSNull) }.mapValues(strip)
        }
        if let a = v as? [Any] { return a.map(strip) }
        return v
    }
    return strip(try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as! NSObject
}

/// Decodes `json` as a `T`, and checks it writes back as the same JSON, so
/// no field is misspelled, missing or extra.
func roundTrip<T: Codable>(_ type: T.Type, _ json: String) throws {
    let data = Data(json.utf8)
    let value = try decoder.decode(T.self, from: data)
    let back = try encoder.encode(value)
    #expect(try plain(back) == plain(data), "\(json)")
}

@Test func everyAnswerExampleDecodesAndWritesBack() throws {
    var seen = Set<String>()
    for (kind, json) in try examples() {
        seen.insert(kind)
        switch kind {
        case "hello": try roundTrip(Hello.self, json)
        case "status": try roundTrip(Status.self, json)
        case "peers": try roundTrip([Peer].self, json)
        case "init": try roundTrip(Created.self, json)
        case "invite": try roundTrip(Invite.self, json)
        case "join": try roundTrip(Joined.self, json)
        case "leave": try roundTrip(Left.self, json)
        case "change": try roundTrip(Change.self, json)
        case "pending": try roundTrip([Proposal].self, json)
        case "config": try roundTrip(Config.self, json)
        case "request", "response": break
        default: Issue.record("unknown example kind \(kind)")
        }
    }
    #expect(seen.isSuperset(of: ["hello", "status", "peers", "change", "pending", "leave", "join"]))
}

@Test func theDocNamesThisAPIVersion() throws {
    #expect(try apiDoc().contains("`hello` answers `api`, one integer, now `\(apiVersion)`"))
}

@Test func requestsAreWrittenAsTheDocShows() throws {
    let documented = try examples().filter { $0.kind == "request" }.map { try plain(Data($0.json.utf8)) }
    let proposal = "6a1f0e2c9d3b4a5f6e7d8c9b0a1f2e3d4c5b6a7f8e9d0c1b2a3f4e5d6c7b8a9f"
    let requests: [Request] = [
        .hello, .status, .peers, .invite, .pending, .configGet,
        .initialize(ipv4Range: "100.80.11.0/24", strictSecurity: false),
        .join(token: "cc1AAAA..."),
        .remove(node: "hypnos"),
        .leave(force: false),
        .approve(proposal: proposal),
        .reject(proposal: proposal),
    ]
    for request in requests {
        let line = try plain(request.line())
        #expect(documented.contains(line), "\(request) is not in the doc as \(line)")
    }
}

@Test func errorAnswersBecomeDaemonErrors() throws {
    #expect(throws: APIError.daemon("no member matches \"zz\"")) {
        let _: Status = try Session.decode(Data(#"{"err":"no member matches \"zz\""}"#.utf8))
    }
}
