import Foundation
import Darwin
@main struct Tests {
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
  let f=root.appendingPathComponent("a file.txt"); try Data("123456789".utf8).write(to:f)
  let vectors:[ChecksumAlgorithm:String] = [.sfv:"CBF43926",.md5:"25f9e794323b453885f5181f1b624d0b",.sha1:"f7c3bc1d808e04732adf679965ccc34ca7ae3441",.sha256:"15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225"]
  for (alg,expected) in vectors {
   let hash = try ChecksumService.digest(f,algorithm:alg); precondition(hash == expected)
   let m=root.appendingPathComponent("checksum."+alg.rawValue)
   try ChecksumService.create(sources:[f],destination:m,algorithm:alg)
   let results = try ChecksumService.verify(manifest:m,algorithm:alg); precondition(results.first?.1 == "OK")
  }
  try Data("changed".utf8).write(to:f)
  let changed = try ChecksumService.verify(manifest:root.appendingPathComponent("checksum.sha256"),algorithm:.sha256); precondition(changed.first?.1 == "MISMATCH")
  do { _ = try ChecksumService.parse(String(repeating:"a",count:64)+" *../outside",algorithm:.sha256); fatalError("traversal accepted") } catch {}
  let special = root.appendingPathComponent("pipe.sha256"); precondition(mkfifo(special.path,0o600) == 0)
  do { _ = try ChecksumService.verify(manifest:special,algorithm:.sha256); fatalError("FIFO accepted") } catch {}
  let comment = root.appendingPathComponent(";comment.txt"); try Data("x".utf8).write(to:comment)
  do { try ChecksumService.create(sources:[comment],destination:root.appendingPathComponent("comment.sfv"),algorithm:.sfv); fatalError("SFV comment accepted") } catch {}
  print("Checksum tests passed: 4 known vectors, manifest round trips, mismatch and traversal")
 }
}
