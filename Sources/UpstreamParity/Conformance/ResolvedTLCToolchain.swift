import Foundation

package struct ResolvedTLCToolchain: Sendable {
  package let java: URL
  package let jar: URL
  package let bridgeJar: URL
  package let artifacts: TLCReferenceArtifacts

  package init(toolRoot: URL, projectRoot: URL, pin: TLCReferencePin) throws {
    let armJava = toolRoot.appendingPathComponent("java-arm64/Contents/Home/bin/java")
    let architecture = FileManager.default.fileExists(atPath: armJava.path) ? "arm64" : "x86_64"
    java = toolRoot.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
    jar = toolRoot.appendingPathComponent("downloads/tla2tools.jar")
    bridgeJar = toolRoot.appendingPathComponent("bridge.jar")
    let archive = toolRoot.appendingPathComponent("downloads/temurin-\(architecture).tar.gz")
    let sources = Dictionary(uniqueKeysWithValues: pin.bridgeSourceHashes.keys.map { ($0, projectRoot.appendingPathComponent($0)) })
    artifacts = try TLCReferenceInspector.inspect(
      artifacts: TLCReferenceArtifacts(
        jar: jar, javaArchive: archive, bridgeSources: sources, bridgeBinary: bridgeJar,
        jarManifest: "", runtime: .init(version: "", vendor: "", architecture: architecture, properties: [:])),
      javaExecutable: java, directory: projectRoot)
    try pin.validate(artifacts)
  }
}
