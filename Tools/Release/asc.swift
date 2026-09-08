// App Store Connect API 호출기. ES256 JWT를 CryptoKit으로 만들고 JSON:API를 그대로 주고받는다.
//
//   ASC_KEY_PATH=~/Downloads/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=... \
//   swift Tools/Release/asc.swift get  /v1/apps?filter[bundleId]=com.example
//   swift Tools/Release/asc.swift post /v1/betaGroups '{"data":{...}}'
//   swift Tools/Release/asc.swift patch /v1/... '{...}'
//   swift Tools/Release/asc.swift delete /v1/...
import Foundation
import CryptoKit

func env(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        FileHandle.standardError.write("\(name) 환경 변수가 필요하다\n".data(using: .utf8)!); exit(2)
    }
    return value
}

func base64url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func makeToken() throws -> String {
    let keyPath = (env("ASC_KEY_PATH") as NSString).expandingTildeInPath
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let header = ["alg": "ES256", "kid": env("ASC_KEY_ID"), "typ": "JWT"]
    let now = Int(Date().timeIntervalSince1970)
    let payload: [String: Any] = ["iss": env("ASC_ISSUER_ID"), "iat": now, "exp": now + 15 * 60,
                                  "aud": "appstoreconnect-v1"]
    let h = base64url(try JSONSerialization.data(withJSONObject: header))
    let p = base64url(try JSONSerialization.data(withJSONObject: payload))
    let signature = try key.signature(for: Data("\(h).\(p)".utf8))
    return "\(h).\(p).\(base64url(signature.rawRepresentation))"
}

let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    print("usage: asc.swift <get|post|patch|delete> <path> [json]"); exit(2)
}
let method = args[args.startIndex].uppercased()
let path = args[args.startIndex + 1]
let body = args.count >= 3 ? args[args.startIndex + 2] : nil

var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
request.httpMethod = method
request.setValue("Bearer \(try makeToken())", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
if let body { request.httpBody = body.data(using: .utf8) }

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let error { print("네트워크 오류: \(error)"); exitCode = 1; return }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if let data, !data.isEmpty,
       let object = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: pretty, as: UTF8.self))
    }
    if status >= 300 { print("HTTP \(status)"); exitCode = 1 }
}.resume()
semaphore.wait()
exit(exitCode)
