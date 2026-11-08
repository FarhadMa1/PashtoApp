import Foundation
import Testing

/// The manual TestFlight workflow is dispatch-only, fails a real release
/// validation, and keeps the API key out of pull-request runs.
struct TestFlightWorkflowTests {
    @Test func testFlightWorkflowIsManualAndStrict() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/testflight.yml"),
            encoding: .utf8
        )
        let appBuild = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/app-build.yml"),
            encoding: .utf8
        )

        let triggers = keys(in: block("on", of: workflow), atIndent: 2)
        #expect(triggers == ["workflow_dispatch"])
        #expect(workflow.contains("pull_request:") == false)
        #expect(workflow.contains("\npush:") == false)
        #expect(workflow.contains("schedule:") == false)
        #expect(workflow.contains("workflow_call:") == false)

        let permissions = block("permissions", of: workflow)
        #expect(permissions.contains("  contents: read"))
        #expect(workflow.contains("contents: write") == false)
        #expect(workflow.contains("id-token:") == false)
        #expect(workflow.contains("actions: write") == false)

        #expect(workflow.contains("runs-on: macos-15"))
        #expect(workflow.contains("environment: testflight"))
        #expect(workflow.contains("timeout-minutes: 90"))
        #expect(workflow.contains("cancel-in-progress: false"))
        #expect(workflow.contains("concurrency:"))

        let xcodeUse = "uses: maxim-lobanov/setup-xcode@ed7a3b1fda3918c0306d1b724322adc0b8cc0a90"
        #expect(appBuild.contains(xcodeUse))
        #expect(workflow.contains(xcodeUse))
        #expect(workflow.contains("xcode-version: \"26.3\""))
        #expect(appBuild.contains("xcode-version: \"26.3\""))

        let merge = workflow.range(of: "pashto-content merge --check")
        let validate = workflow.range(of: "pashto-content validate --mode release")
        let archive = workflow.range(of: "xcodebuild archive")
        let exportCommand = workflow.range(of: "xcodebuild -exportArchive")
        #expect(merge != nil)
        #expect(validate != nil)
        #expect(archive != nil)
        #expect(exportCommand != nil)
        #expect(merge!.lowerBound < validate!.lowerBound)
        #expect(validate!.lowerBound < archive!.lowerBound)
        #expect(archive!.lowerBound < exportCommand!.lowerBound)

        let checkScript = runScript(containing: "pashto-content validate --mode release", in: workflow)
        #expect(checkScript.contains("set -euo pipefail"))
        #expect(checkScript.contains("set +x"))
        #expect(checkScript.contains("xcrun swift run --package-path Tools/PashtoContentTool pashto-content merge --check"))
        #expect(checkScript.contains("xcrun swift run --package-path Tools/PashtoContentTool pashto-content validate --mode release"))
        #expect(checkScript.contains("set +e") == false)
        #expect(checkScript.contains("exit 0") == false)
        #expect(checkScript.contains("Findings only warn") == false)

        let uploadScript = runScript(containing: "xcodebuild -exportArchive", in: workflow)
        #expect(uploadScript.contains("set -euo pipefail"))
        #expect(uploadScript.contains("set +x"))
        #expect(uploadScript.contains("umask 077"))
        #expect(uploadScript.contains("chmod 0600"))
        #expect(uploadScript.contains("trap cleanup EXIT"))
        #expect(uploadScript.contains("trap 'exit 130' INT"))
        #expect(uploadScript.contains("trap 'exit 143' TERM"))
        #expect(uploadScript.contains("unset ASC_API_KEY_P8"))
        #expect(uploadScript.contains("printf '%s' \"$ASC_API_KEY_P8\" > \"$key_file\""))
        #expect(uploadScript.contains("${RUNNER_TEMP}/AuthKey_9U5475FGSS.p8"))
        #expect(uploadScript.contains("CODE_SIGNING_ALLOWED=NO"))
        #expect(uploadScript.contains("CODE_SIGNING_REQUIRED=NO"))
        #expect(uploadScript.contains("CODE_SIGN_STYLE=Automatic"))
        #expect(uploadScript.contains("DEVELOPMENT_TEAM=82RFYU3NS3"))
        #expect(uploadScript.contains("CURRENT_PROJECT_VERSION=\"${GITHUB_RUN_NUMBER}\""))
        #expect(uploadScript.contains("-configuration Release"))
        #expect(uploadScript.contains("-destination 'generic/platform=iOS'"))
        #expect(uploadScript.contains("-project PashtoApp.xcodeproj"))
        #expect(uploadScript.contains("-scheme PashtoApp"))
        #expect(uploadScript.contains("<string>app-store-connect</string>"))
        #expect(uploadScript.contains("<string>upload</string>"))
        #expect(uploadScript.contains("<string>automatic</string>"))
        #expect(uploadScript.contains("<string>82RFYU3NS3</string>"))
        #expect(uploadScript.contains("<key>manageAppVersionAndBuildNumber</key>"))
        #expect(uploadScript.contains("<false/>"))
        #expect(uploadScript.contains("-allowProvisioningUpdates"))
        #expect(uploadScript.contains("-authenticationKeyPath \"$key_file\""))
        #expect(uploadScript.contains("-authenticationKeyID \"9U5475FGSS\""))
        #expect(uploadScript.contains("-authenticationKeyIssuerID \"4eb37ecd-e901-443a-8d09-eef88b03d2a8\""))

        let export = uploadScript[exportStart(in: uploadScript)...]
        #expect(export.contains("-allowProvisioningUpdates"))
        #expect(export.contains("-authenticationKeyPath"))
        #expect(export.contains("-authenticationKeyID"))
        #expect(export.contains("-authenticationKeyIssuerID"))
        let archiveHalf = uploadScript[..<exportStart(in: uploadScript)]
        #expect(archiveHalf.contains("-authenticationKeyPath") == false)
        #expect(archiveHalf.contains("DEVELOPMENT_TEAM=82RFYU3NS3"))

        #expect(workflow.contains("echo \"$ASC_API_KEY_P8\"") == false)
        #expect(workflow.contains("echo ${ASC_API_KEY_P8") == false)
        #expect(workflow.contains("set -x") == false)
        #expect(workflow.contains("printenv ASC_API_KEY_P8") == false)

        let secretNames = workflow.matches(of: /\$\{\{\s*secrets\.([A-Za-z0-9_]+)/).map { String($0.1) }
        #expect(secretNames == ["ASC_API_KEY_P8"])

        #expect(workflow.contains("if: always()"))
        let cleanup = runScript(containing: "rm -f \"${RUNNER_TEMP}/AuthKey_9U5475FGSS.p8\"", in: workflow)
        #expect(cleanup.contains("set +x"))
        #expect(cleanup.contains("rm -f \"${RUNNER_TEMP}/AuthKey_9U5475FGSS.p8\""))
        #expect(cleanup.contains("xcodebuild") == false)
    }

    @Test func releasePullRequestGateStaysWarningOnly() throws {
        let gate = try String(
            contentsOf: repositoryRoot().appendingPathComponent(".github/workflows/swift-test.yml"),
            encoding: .utf8
        )
        #expect(gate.contains("Findings only warn, so error lines (exit 1) and warning lines (exit 0) keep the job green."))
        #expect(gate.contains("exit 0"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func block(_ key: String, of workflow: String) -> [String] {
    let lines = workflow.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var index = 0
    while index < lines.count {
        if lines[index] == "\(key):" {
            index += 1
            var body: [String] = []
            while index < lines.count {
                let line = lines[index]
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(" ") || line.hasPrefix("\t") {
                    body.append(line)
                    index += 1
                    continue
                }
                break
            }
            return body
        }
        index += 1
    }
    return []
}

private func keys(in lines: [String], atIndent indent: Int) -> [String] {
    let prefix = String(repeating: " ", count: indent)
    let deeper = String(repeating: " ", count: indent + 1)
    return lines.compactMap { line in
        guard line.hasPrefix(prefix), line.hasPrefix(deeper) == false, line.hasPrefix("\(prefix)#") == false else {
            return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        return String(trimmed[..<colon])
    }
}

private func runScript(containing needle: String, in workflow: String) -> String {
    let lines = workflow.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [String] = []
    var index = 0
    while index < lines.count {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed == "run: |" {
            let base = lines[index].prefix(while: { $0 == " " }).count
            index += 1
            var body: [String] = []
            while index < lines.count {
                let line = lines[index]
                if line.isEmpty {
                    body.append("")
                    index += 1
                    continue
                }
                let indent = line.prefix(while: { $0 == " " }).count
                if indent <= base {
                    break
                }
                body.append(String(line.dropFirst(base + 2)))
                index += 1
            }
            blocks.append(body.joined(separator: "\n"))
            continue
        }
        index += 1
    }
    return blocks.first { $0.contains(needle) } ?? ""
}

private func exportStart(in script: String) -> String.Index {
    script.range(of: "xcodebuild -exportArchive")?.lowerBound ?? script.endIndex
}
