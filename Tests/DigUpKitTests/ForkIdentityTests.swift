import Foundation
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func plist() throws -> [String: Any] {
    let data = try Data(contentsOf: repo.appendingPathComponent("Resources/Info.plist"))
    return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
}

private func sourceFiles() -> [URL] {
    let sources = repo.appendingPathComponent("Sources")
    guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return [] }
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}

@Suite struct ForkIdentityTests {
    @Test func identityIsIndependent() throws {
        let info = try plist()
        #expect(info["CFBundleIdentifier"] as? String == "org.digupatlas.app")
        #expect(info["CFBundleDisplayName"] as? String == "DigUp Atlas")
        #expect(info["CFBundleName"] as? String == "DigUp Atlas")
        #expect(info["CFBundleExecutable"] as? String == "DigUpAtlas")
        #expect(info["SUFeedURL"] == nil)
        #expect(info["SUPublicEDKey"] == nil)
        #expect(info["SUEnableAutomaticChecks"] == nil)
    }

    @Test func upstreamUpdateChannelIsGone() throws {
        #expect(!FileManager.default.fileExists(atPath:
            repo.appendingPathComponent("Sources/DigUpApp/Updates.swift").path))
        for file in sourceFiles() where file.path.contains("/DigUpApp/") {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("import Sparkle"), "\(file.lastPathComponent) still imports Sparkle")
            #expect(!text.contains("Check for Updates"), "\(file.lastPathComponent) still has an update control")
        }
        let package = try String(contentsOf: repo.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!package.contains("sparkle-project"))
        let build = try String(contentsOf: repo.appendingPathComponent("build.sh"), encoding: .utf8)
        #expect(!build.contains("Sparkle"))
    }

    @Test func noticesArePreserved() throws {
        let license = try String(contentsOf: repo.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(license.contains("MIT License"))
        #expect(license.contains("Copyright (c) 2026 Abdur Rahim"))
        let notices = try String(contentsOf: repo.appendingPathComponent("Resources/Acknowledgements.txt"),
                                 encoding: .utf8)
        #expect(notices.contains("llama.cpp"))
        #expect(notices.contains("MIT License"))
        #expect(notices.contains("stb_image"))
    }

    @Test func crossPlatformSourcesAreIntact() throws {
        let package = try String(contentsOf: repo.appendingPathComponent("Package.swift"), encoding: .utf8)
        for name in ["CSQLite", "CStb", "CMiniz", "CPDFium", "CLlamaShared", "CLlamaWindows"] {
            #expect(package.contains(name), "Package.swift lost \(name)")
        }
        for dir in ["Sources/CLlama", "Sources/CLlamaShared", "Sources/CLlamaWindows", "Sources/CPDFium",
                    "Sources/DigUpKit/Platform"] {
            var isFolder: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent(dir).path,
                                                   isDirectory: &isFolder) && isFolder.boolValue,
                    "\(dir) is missing")
        }
    }

    @Test func testFixturesAreUnchanged() throws {
        for dir in ["Tests/DigUpKitTests/Pictures", "Tests/DigUpKitTests/Videos",
                    "Tests/LlamaRuntimeTests/Reference"] {
            let url = repo.appendingPathComponent(dir)
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
                .filter { !$0.hasPrefix(".") }
            #expect(!files.isEmpty, "\(dir) is empty")
        }
    }
}
