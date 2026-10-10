import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Match: Identifiable {
    var id: String { url.absoluteString }
    let site: String
    let url: URL
}

enum SearchOutput {
    static func match(_ line: String) -> Match? {
        guard line.hasPrefix("[+] "), let boundary = line.range(of: ": http") else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: 4)..<boundary.lowerBound])
        let address = String(line[line.index(boundary.lowerBound, offsetBy: 2)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let url = URL(string: address), ["https", "http"].contains(url.scheme), url.host != nil else { return nil }
        return Match(site: name, url: url)
    }
    static func validUsername(_ input: String) -> Bool {
        !input.isEmpty && input.count <= 100 && !input.hasPrefix("-") &&
        input.range(of: "^[\\p{L}\\p{N}_.-]+$", options: .regularExpression) != nil
    }
    static func csv(_ value: String) -> String {
        let safe = ["=", "+", "-", "@", "\t", "\r"].contains(String(value.prefix(1))) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

final class SearchModel: ObservableObject {
    @Published var username = ""
    @Published var matches: [Match] = []
    @Published var running = false
    @Published var status = "Ready to search"
    @Published var searchedUsername = ""
    @Published var log = ""
    @Published var error: String?
    @Published var checked = 0
    @Published var unavailable = 0
    @Published var startedAt: Date?
    @Published var elapsed: TimeInterval = 0
    private var child: Process?
    private var cancelled = false
    private var timer: Timer?
    private var directory: URL?
    let executable: URL
    init(executable: URL? = nil) {
        self.executable = executable ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/sherlock")
    }
    var installed: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    func search() {
        guard !running else { return }
        var name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("@") { name.removeFirst() }
        guard SearchOutput.validUsername(name) else {
            error = "Enter one username using letters, numbers, dots, underscores, or hyphens. Don’t enter a URL or start with a hyphen."
            return
        }
        guard installed else {
            error = "Sherlock could not be found at \(executable.path). This app uses the Sherlock installation on your Mac."
            return
        }
        username = name; searchedUsername = name; matches = []; log = ""; checked = 0; unavailable = 0
        error = nil; cancelled = false; elapsed = 0
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--no-color", "--print-all", "--timeout", "15", name]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("SherlockDesktop-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription; return }
        directory = scratch; process.currentDirectoryURL = scratch
        do { try process.run() }
        catch {
            self.error = "Could not start Sherlock: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: scratch); directory = nil
            return
        }
        child = process; running = true; status = "Searching public profiles…"; startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startedAt else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }
        // Read on one background queue, preserving byte and line ordering.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pending = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let data = pending[..<newline]
                    let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
                    pending.removeSubrange(...newline)
                    DispatchQueue.main.async { self?.consume(line) }
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                DispatchQueue.main.async { self?.consume(line) }
            }
            process.waitUntilExit()
            let code = process.terminationStatus
            try? pipe.fileHandleForReading.close()
            DispatchQueue.main.async { self?.finish(code) }
        }
    }

    func consume(_ line: String) {
        // Remove terminal control sequences before displaying plain text.
        let clean = line.replacingOccurrences(of: "\u{001B}\\][^\u{001B}\u{0007}]*(?:\u{0007}|\u{001B}\\\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        log += clean + "\n"
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
        if clean.hasPrefix("[+] ") || clean.hasPrefix("[-] ") { checked += 1 }
        if clean.hasPrefix("[-] ") && !clean.contains("Not Found!") { unavailable += 1 }
        if let result = SearchOutput.match(clean), !matches.contains(where: { $0.id == result.id }) {
            matches.append(result)
        }
    }

    func stop() {
        guard let process = child, process.isRunning else { return }
        cancelled = true; status = "Stopping search…"
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func finish(_ code: Int32) {
        timer?.invalidate(); timer = nil
        running = false; child = nil
        if let start = startedAt { elapsed = Date().timeIntervalSince(start) }
        if cancelled { status = "Stopped · partial results" }
        else if code != 0 {
            status = "Search interrupted"
            error = "Sherlock exited with code \(code). Any matches below are partial. Open Search details for the error output."
        } else if checked == 0 {
            status = "No site results returned"
            error = "Sherlock did not return any site checks. Open Search details to see whether setup or network access failed."
        } else { status = unavailable > 0 ? "Finished · some sites could not be checked" : "Search finished" }
        if let directory = directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "sherlock-\(searchedUsername).csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let header = "Username,Site,URL,Search status\r\n"
        let rows = matches.map { [searchedUsername, $0.site, $0.url.absoluteString, running ? "In progress (partial)" : status].map(SearchOutput.csv).joined(separator: ",") }.joined(separator: "\r\n")
        do { try (header + rows + "\r\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = "Export failed: \(error.localizedDescription)" }
    }
}

struct ContentView: View {
    @StateObject private var model = SearchModel()
    @State private var filter = ""
    @State private var details = false
    @FocusState private var usernameFocused: Bool
    private let accent = Color(red: 0.24, green: 0.41, blue: 0.94)
    private var filtered: [Match] {
        model.matches.filter { filter.isEmpty || $0.site.localizedCaseInsensitiveContains(filter) || $0.url.absoluteString.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.site.localizedCaseInsensitiveCompare($1.site) == .orderedAscending }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 46)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sherlock").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("DESKTOP").font(.system(size: 10, weight: .bold)).tracking(3).foregroundStyle(.secondary)
                }
                Text("Find a username\nacross the web.").font(.title3.weight(.medium)).lineSpacing(4)
                Divider()
                Label("Public profiles", systemImage: "globe").font(.callout)
                Label("Runs on your Mac", systemImage: "desktopcomputer").font(.callout)
                Text("Searches contact supported websites through Sherlock. Results stay in this window unless you export them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Label(model.installed ? "Sherlock connected" : "Sherlock missing", systemImage: model.installed ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(model.installed ? Color.green : Color.orange)
                Link("Open-source Sherlock ↗", destination: URL(string: "https://github.com/sherlock-project/sherlock")!).font(.caption)
                Text("An independent interface for Sherlock.").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(26).frame(width: 224).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username search").font(.system(size: 26, weight: .semibold))
                    Text("Enter a username to look for matching public profiles.").foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "at").foregroundStyle(.secondary)
                        TextField("Username, e.g. your_handle", text: $model.username)
                            .textFieldStyle(.plain).font(.body).focused($usernameFocused)
                            .onSubmit { if !model.running { filter = ""; model.search() } }
                            .disabled(model.running).accessibilityLabel("Username")
                    }.padding(12).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                    if model.running {
                        Button(action: model.stop) { Label("Stop", systemImage: "stop.fill").frame(minWidth: 75) }.controlSize(.large)
                    } else {
                        Button { filter = ""; model.search() } label: { Label("Search", systemImage: "magnifyingglass").frame(minWidth: 75) }
                            .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                            .disabled(model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if model.running { ProgressView().controlSize(.small) }
                    else { Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(model.error == nil ? accent : .orange) }
                    Text(model.status).font(.callout)
                    Spacer()
                    if model.startedAt != nil { Text("\(Int(model.elapsed))s").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                if model.startedAt != nil {
                    HStack(spacing: 22) {
                        metric("\(model.matches.count)", "matches")
                        metric("\(model.checked)", "site responses")
                        metric("\(model.unavailable)", "unavailable / skipped")
                        Spacer()
                    }
                }
                Divider()
                HStack {
                    Text("\(model.matches.count) matches").font(.headline)
                    Spacer()
                    TextField("Filter sites", text: $filter).textFieldStyle(.roundedBorder).frame(width: 150)
                    Button(action: model.export) { Label("Export CSV", systemImage: "square.and.arrow.up") }.disabled(model.matches.isEmpty)
                }
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: model.running ? "antenna.radiowaves.left.and.right" : "person.crop.circle")
                            .font(.system(size: 39, weight: .light)).foregroundStyle(accent.opacity(0.75))
                        Text(emptyTitle).font(.title3.weight(.medium))
                        Text(emptySubtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { item in
                                HStack(spacing: 12) {
                                    Text(String(item.site.prefix(1)).uppercased()).font(.headline).foregroundStyle(accent)
                                        .frame(width: 35, height: 35).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.site).font(.body.weight(.semibold))
                                        Text(item.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 8)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
                                    } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy profile URL").accessibilityLabel("Copy \(item.site) URL")
                                    Link(destination: item.url) { Image(systemName: "arrow.up.right.square") }.help("Open profile").accessibilityLabel("Open \(item.site)")
                                }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("A matching username does not confirm identity. Some sites may block requests or return false matches.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Search details", isExpanded: $details) {
                        ScrollView {
                            Text(model.log.isEmpty ? "Search output will appear here." : model.log)
                                .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }.frame(height: 105).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 670)
        .onAppear { usernameFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var emptyTitle: String {
        if !filter.isEmpty { return "No sites match your filter" }
        if model.running { return "Looking for matches…" }
        if model.startedAt != nil { return "No matches returned" }
        return "Your results will appear here"
    }
    private var emptySubtitle: String {
        if !filter.isEmpty { return "Try another site name or clear the filter." }
        if model.running { return "Results appear as Sherlock checks each site. Larger searches can take a few minutes." }
        if model.startedAt != nil { return "This does not prove the username is unused. Review Search details for unavailable sites or errors." }
        return "Start with your own username to explore where it appears online."
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SherlockDesktop: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        if let argument = CommandLine.arguments.firstIndex(of: "--integration-test"), CommandLine.arguments.count > argument + 1 {
            let model = SearchModel(executable: URL(fileURLWithPath: CommandLine.arguments[argument + 1]))
            func waitForFinish() {
                let deadline = Date().addingTimeInterval(12)
                while model.running && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
                precondition(!model.running, "Search did not finish")
            }
            model.username = "fixture"; model.search()
            precondition(model.running, "Subprocess did not start")
            waitForFinish()
            precondition(model.matches.count == 2 && model.checked == 4 && model.unavailable == 1, "Incorrect subprocess results")
            precondition(model.error == nil, "Successful search produced an error")
            model.username = "failure"; model.search(); waitForFinish()
            precondition(model.error != nil && model.status == "Search interrupted", "Failed exit was not surfaced")
            model.username = "slow"; model.search()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            model.stop(); waitForFinish()
            precondition(model.status == "Stopped · partial results", "Cancellation failed")
            print("PASS: real subprocess streaming, completion, failure handling, restart, and cancellation (synthetic data, no network)")
            exit(0)
        }
        if CommandLine.arguments.contains("--self-test") {
            precondition(SearchOutput.validUsername("example_user.1"))
            precondition(!SearchOutput.validUsername("--help"))
            precondition(!SearchOutput.validUsername("https://example.com"))
            precondition(!SearchOutput.validUsername("a; touch bad"))
            let result = SearchOutput.match("[+] Example: https://example.com/user")
            precondition(result?.site == "Example" && result?.url.host == "example.com")
            precondition(SearchOutput.match("[-] Example: Not Found!") == nil)
            precondition(SearchOutput.match("[+] Example: file:///tmp/test") == nil)
            precondition(SearchOutput.csv("=SUM(1)") == "\"'=SUM(1)\"")
            let model = SearchModel()
            model.consume("[+] Example: https://example.com/user")
            model.consume("[+] Example: https://example.com/user")
            model.consume("[-] Other: Not Found!")
            model.consume("[-] Blocked: Blocked by bot detection")
            precondition(model.matches.count == 1 && model.checked == 4 && model.unavailable == 1)
            print("PASS: username validation, result parsing, URL restriction, CSV escaping, deduplication, and unavailable-site tracking")
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Sherlock Desktop") { ContentView() }
            .defaultSize(width: 980, height: 740)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
