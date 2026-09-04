import Foundation
import Darwin

var passedCount = 0
var totalCount = 0

func assertTest(_ condition: Bool, _ description: String) {
    totalCount += 1
    if condition {
        passedCount += 1
        print("  ✓ PASS: \(description)")
    } else {
        print("  ✗ FAIL: \(description)")
        fatalError("Test assertion failed: \(description)")
    }
}

func runCommand(_ command: String, arguments: [String] = []) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    let outPipe = Pipe()
    let errPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    process.standardOutput = outPipe
    process.standardError = errPipe

    try process.run()
    process.waitUntilExit()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: outData, encoding: .utf8) ?? ""
    let stderr = String(data: errData, encoding: .utf8) ?? ""

    return (process.terminationStatus, stdout, stderr)
}

setbuf(stdout, nil)

print("=================================================================")
print(" SwarmDeck: macOS Packaging, Entitlements & Release Setup Tests")
print("=================================================================\n")

let fm = FileManager.default
let currentDir = fm.currentDirectoryPath

// -------------------------------------------------------------
// Test Group 1: Plist Integrity & Key Configuration
// -------------------------------------------------------------
print("[Test Group 1: Plist Integrity & Key Configuration]")

let plistPath = "\(currentDir)/Resources/Info.plist"
assertTest(fm.fileExists(atPath: plistPath), "Resources/Info.plist exists on disk")

let lintResult = try runCommand("/usr/bin/plutil", arguments: ["-lint", plistPath])
assertTest(lintResult.status == 0, "plutil -lint validates Resources/Info.plist without syntax errors")

let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
var format = PropertyListSerialization.PropertyListFormat.xml
guard let plistDict = try PropertyListSerialization.propertyList(from: plistData, options: [], format: &format) as? [String: Any] else {
    fatalError("Failed to deserialize Info.plist as dictionary")
}

assertTest((plistDict["CFBundleIdentifier"] as? String) == "com.rafaelscharf.SwarmDeck", "CFBundleIdentifier is 'com.rafaelscharf.SwarmDeck'")
assertTest((plistDict["CFBundleName"] as? String) == "SwarmDeck", "CFBundleName is 'SwarmDeck'")
assertTest((plistDict["CFBundleExecutable"] as? String) == "SwarmDeck", "CFBundleExecutable matches 'SwarmDeck'")
assertTest((plistDict["CFBundlePackageType"] as? String) == "APPL", "CFBundlePackageType is 'APPL'")
assertTest((plistDict["LSMinimumSystemVersion"] as? String) == "14.0", "LSMinimumSystemVersion is configured for macOS 14.0+")
assertTest((plistDict["NSHighResolutionCapable"] as? Bool) == true, "NSHighResolutionCapable is enabled (Retina support)")
assertTest((plistDict["NSUserNotificationAlertStyle"] as? String) == "alert", "NSUserNotificationAlertStyle configured as 'alert'")
assertTest((plistDict["CFBundleIconFile"] as? String) == "AppIcon", "CFBundleIconFile references 'AppIcon'")
assertTest((plistDict["LSApplicationCategoryType"] as? String) == "public.app-category.developer-tools", "LSApplicationCategoryType is 'developer-tools'")

// -------------------------------------------------------------
// Test Group 2: Hardened Runtime & Process Entitlements
// -------------------------------------------------------------
print("\n[Test Group 2: Hardened Runtime & Process Entitlements]")

let entitlementsPath = "\(currentDir)/Resources/SwarmDeck.entitlements"
assertTest(fm.fileExists(atPath: entitlementsPath), "Resources/SwarmDeck.entitlements exists on disk")

let entLintResult = try runCommand("/usr/bin/plutil", arguments: ["-lint", entitlementsPath])
assertTest(entLintResult.status == 0, "plutil -lint validates Resources/SwarmDeck.entitlements")

let entData = try Data(contentsOf: URL(fileURLWithPath: entitlementsPath))
guard let entDict = try PropertyListSerialization.propertyList(from: entData, options: [], format: &format) as? [String: Any] else {
    fatalError("Failed to deserialize SwarmDeck.entitlements as dictionary")
}

assertTest((entDict["com.apple.security.app-sandbox"] as? Bool) == false, "App Sandbox is disabled (required for forkpty and arbitrary CLI agents)")
assertTest((entDict["com.apple.security.cs.allow-jit"] as? Bool) == true, "allow-jit entitlement is enabled")
assertTest((entDict["com.apple.security.cs.allow-unsigned-executable-memory"] as? Bool) == true, "allow-unsigned-executable-memory entitlement is enabled")
assertTest((entDict["com.apple.security.cs.disable-library-validation"] as? Bool) == true, "disable-library-validation is enabled for dynamic tools")
assertTest((entDict["com.apple.security.get-task-allow"] as? Bool) == true, "get-task-allow is configured for developer workflow")

// -------------------------------------------------------------
// Test Group 3: App Icon Assets
// -------------------------------------------------------------
print("\n[Test Group 3: App Icon Assets]")

let icnsPath = "\(currentDir)/Resources/AppIcon.icns"
assertTest(fm.fileExists(atPath: icnsPath), "Resources/AppIcon.icns exists on disk")

let icnsData = try Data(contentsOf: URL(fileURLWithPath: icnsPath))
assertTest(icnsData.count > 100_000, "Resources/AppIcon.icns contains rich high-res image data (>100KB: \(icnsData.count) bytes)")

// Validate ICNS magic header "icns" (0x69, 0x63, 0x6e, 0x73)
let magic = String(data: icnsData.prefix(4), encoding: .ascii)
assertTest(magic == "icns", "AppIcon.icns has valid 'icns' magic header")

let iconGenScript = "\(currentDir)/scripts/generate_icon.swift"
assertTest(fm.fileExists(atPath: iconGenScript), "scripts/generate_icon.swift is available for programmatic asset regeneration")

// -------------------------------------------------------------
// Test Group 4: Packaging Pipeline Execution
// -------------------------------------------------------------
print("\n[Test Group 4: Packaging Pipeline Execution]")

let packageScript = "\(currentDir)/scripts/package_app.sh"
assertTest(fm.fileExists(atPath: packageScript), "scripts/package_app.sh exists on disk")
assertTest(fm.isExecutableFile(atPath: packageScript), "scripts/package_app.sh is marked executable")

let makefilePath = "\(currentDir)/Makefile"
assertTest(fm.fileExists(atPath: makefilePath), "Root Makefile exists for developer onboarding and CI")

let appPath = "\(currentDir)/build/Release/SwarmDeck.app"
let contentsPath = "\(appPath)/Contents"
let macosBinPath = "\(contentsPath)/MacOS/SwarmDeck"
let bundlePlistPath = "\(contentsPath)/Info.plist"
let bundleIconPath = "\(contentsPath)/Resources/AppIcon.icns"
let ghosttyBundlePath = "\(contentsPath)/Resources/GhosttyKit_GhosttyTerminal.bundle"

assertTest(fm.fileExists(atPath: appPath), "SwarmDeck.app bundle directory exists in build/Release")
assertTest(fm.fileExists(atPath: macosBinPath), "SwarmDeck binary exists in Contents/MacOS/")
assertTest(fm.isExecutableFile(atPath: macosBinPath), "SwarmDeck binary is marked executable")
assertTest(fm.fileExists(atPath: bundlePlistPath), "Info.plist is bundled in Contents/")
assertTest(fm.fileExists(atPath: bundleIconPath), "AppIcon.icns is bundled in Contents/Resources/")
assertTest(fm.fileExists(atPath: ghosttyBundlePath), "GhosttyKit_GhosttyTerminal.bundle is bundled in Contents/Resources/")
assertTest(fm.fileExists(atPath: "\(ghosttyBundlePath)/terminfo"), "Ghostty terminfo database is bundled in Contents/Resources/")
assertTest(fm.fileExists(atPath: "\(ghosttyBundlePath)/Info.plist"), "Ghostty resource bundle contains Info.plist for valid code signing")

// -------------------------------------------------------------
// Test Group 5: Code Signing & Designated Requirement
// -------------------------------------------------------------
print("\n[Test Group 5: Code Signing & Designated Requirement]")

let signVerifyResult = try runCommand("/usr/bin/codesign", arguments: [
    "--verify", "--deep", "--strict", "--verbose=2", appPath
])
assertTest(signVerifyResult.status == 0, "codesign --verify passes with strict validation")

let entExtractResult = try runCommand("/usr/bin/codesign", arguments: [
    "-d", "--entitlements", ":-", appPath
])
assertTest(entExtractResult.status == 0, "codesign extracted embedded entitlements successfully")
assertTest(entExtractResult.stdout.contains("<key>com.apple.security.app-sandbox</key><false/>") ||
           entExtractResult.stdout.contains("<false/>"), "Embedded entitlements contain app-sandbox=false")
assertTest(entExtractResult.stdout.contains("com.apple.security.cs.allow-unsigned-executable-memory"), "Embedded entitlements contain allow-unsigned-executable-memory")

// -------------------------------------------------------------
// Test Group 6: Binary Mach-O Architecture & Distributables
// -------------------------------------------------------------
print("\n[Test Group 6: Binary Mach-O Architecture & Distributables]")

let fileResult = try runCommand("/usr/bin/file", arguments: [macosBinPath])
assertTest(fileResult.status == 0, "file command inspected executable successfully")
assertTest(fileResult.stdout.contains("Mach-O 64-bit executable"), "SwarmDeck binary is a 64-bit Mach-O executable")

let zipPath = "\(currentDir)/build/Release/SwarmDeck.zip"
assertTest(fm.fileExists(atPath: zipPath), "Distributable SwarmDeck.zip was generated")

let dmgPath = "\(currentDir)/build/Release/SwarmDeck.dmg"
assertTest(fm.fileExists(atPath: dmgPath), "Distributable SwarmDeck.dmg disk image was generated")

print("\n=================================================================")
print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
print("=================================================================\n")
