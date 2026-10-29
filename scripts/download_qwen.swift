// Download pinned, verified weights using macOS networking, with resumable independent ranges.
import Foundation
import CryptoKit

let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/声笺/ASR/models/Qwen3-ASR-1.7B-8bit")
let target = root.appendingPathComponent("model.safetensors")
let parts = root.appendingPathComponent(".download-1mb-parts")
let size = 2_463_307_541, chunkSize = 1_048_576
let expectedHash = "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"
// Both repository revisions publish the same SHA-256, checked again before the final file is exposed.
let sources = [
    "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/model.safetensors",
    "https://modelscope.cn/models/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/579e237ce6ec925252973afe835d2f98a138602f/model.safetensors"
]
try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
let configuration = URLSessionConfiguration.ephemeral
configuration.httpMaximumConnectionsPerHost = 12
configuration.timeoutIntervalForRequest = 60
configuration.timeoutIntervalForResource = 180
let session = URLSession(configuration: configuration)
let group = DispatchGroup(), slots = DispatchSemaphore(value: 24), lock = NSLock()
var completed = 0, failed = false
let count = (size + chunkSize - 1) / chunkSize
var verifiedFile = target
func finish(_ success: Bool) {
    lock.lock(); completed += 1; if !success { failed = true }
    if completed % 16 == 0 || completed == count { print("Model parts: \(completed)/\(count)"); fflush(stdout) }
    lock.unlock(); slots.signal(); group.leave()
}
func download(_ index: Int, attempt: Int = 0) {
    let start = index * chunkSize, end = min(size, start + chunkSize) - 1
    let file = parts.appendingPathComponent(String(index))
    let source = sources[(index + attempt) % sources.count]
    var request = URLRequest(url: URL(string: source + "?native-part=\(index)&attempt=\(attempt)")!)
    request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
    session.dataTask(with: request) { data, response, error in
        let http = response as? HTTPURLResponse
        if error == nil, http?.statusCode == 206,
           http?.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(end)/\(size)",
           let data, data.count == end - start + 1, (try? data.write(to: file, options: .atomic)) != nil {
            finish(true)
        } else if attempt < 10 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(min(10, attempt + 1))) { download(index, attempt: attempt + 1) }
        } else {
            fputs("Unable to download model part \(index)\n", stderr); finish(false)
        }
    }.resume()
}
if !FileManager.default.fileExists(atPath: target.path) {
    for index in 0..<count {
        slots.wait(); group.enter()
        let file = parts.appendingPathComponent(String(index))
        let expected = min(chunkSize, size - index * chunkSize)
        if (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == expected { finish(true) }
        else { download(index) }
    }
    group.wait(); guard !failed else { exit(1) }
    let temporary = root.appendingPathComponent("model.safetensors.assembling")
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    let output = try FileHandle(forWritingTo: temporary)
    for index in 0..<count { try output.write(contentsOf: Data(contentsOf: parts.appendingPathComponent(String(index)))) }
    try output.close()
    verifiedFile = temporary
}
var hash = SHA256()
let input = try FileHandle(forReadingFrom: verifiedFile)
while let data = try input.read(upToCount: 8 * 1024 * 1024), !data.isEmpty { hash.update(data: data) }
try input.close()
guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expectedHash else {
    fputs("Model checksum mismatch; do not use these weights\n", stderr)
    // Preserve failed downloads for diagnosis, but never expose an unverified final model path.
    try FileManager.default.moveItem(at: verifiedFile, to: root.appendingPathComponent("model.safetensors.invalid-\(UUID().uuidString)"))
    exit(1)
}
if verifiedFile != target { try FileManager.default.moveItem(at: verifiedFile, to: target) }
print("Model SHA-256 verified")
