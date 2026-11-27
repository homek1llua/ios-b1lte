// Ign1te — the jailbreak control panel of the Galaxy S10 iOS port (ios-b1lte).
// The kernel is ours, so nothing here is an exploit: the buttons write kern.b2l_jbctl, which the kernel answers
// only for /Applications/Ign1te.app (restart SpringBoard, reboot userspace, tweak injection on/off).
// No materials or blurs: on this port only backboardd has the GPU, so everything is plain colours and gradients.

import SwiftUI
import Darwin

// MARK: - Kernel

enum Kernel {
    static func request(_ value: Int32) -> Bool {
        var v = value
        return sysctlbyname("kern.b2l_jbctl", nil, nil, &v, MemoryLayout<Int32>.size) == 0
    }
    static var injection: Bool {
        var v: Int32 = 0
        var n = MemoryLayout<Int32>.size
        return sysctlbyname("kern.b2l_jb_inject", &v, &n, nil, 0) == 0 && v != 0
    }
    static var available: Bool {
        var v: Int32 = 0
        var n = MemoryLayout<Int32>.size
        return sysctlbyname("kern.b2l_jb_inject", &v, &n, nil, 0) == 0
    }
}

// MARK: - SSH

@_silgen_name("posix_spawnattr_set_persona_np")
func spawnattr_set_persona(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ persona: uid_t, _ flags: UInt32) -> Int32
@_silgen_name("posix_spawnattr_set_persona_uid_np")
func spawnattr_set_persona_uid(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ uid: uid_t) -> Int32
@_silgen_name("posix_spawnattr_set_persona_gid_np")
func spawnattr_set_persona_gid(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ gid: gid_t) -> Int32

enum Root {
    /// Runs a command as root (persona 99, uid 0: the kernel grants it to Ign1te). Returns the exit status.
    @discardableResult
    static func run(_ args: [String], wait: Bool = true) -> Int32 {
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        _ = spawnattr_set_persona(&attr, 99, 1)
        _ = spawnattr_set_persona_uid(&attr, 0)
        _ = spawnattr_set_persona_gid(&attr, 0)
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let e = posix_spawn(&pid, args[0], nil, &attr, &argv, environ)
        guard e == 0 else { return Int32(0) - e }
        guard wait else { return 0 }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return status
    }
}

enum SSH {
    static let pidFile = "/var/jb/var/run/sshd.pid"
    static let logFile = "/var/jb/var/log/sshd.log"
    static var running: Bool {
        guard let s = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
    static func start() -> Int32 {
        if running { return 0 }
        return Root.run(["/var/jb/usr/sbin/sshd", "-f", "/var/jb/etc/ssh/sshd_config", "-E", logFile])
    }
    static var log: String {
        let s = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? "(no log yet)"
        return s.split(separator: "\n").suffix(6).joined(separator: "\n")
    }
    static var address: String {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return "no Wi-Fi address" }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            if let a = i.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), String(cString: i.pointee.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                return String(cString: host)
            }
            p = i.pointee.ifa_next
        }
        return "no Wi-Fi address"
    }
}

// MARK: - Package managers

struct PackageManager: Identifiable {
    let id: String
    let path: String
    var installed: Bool { FileManager.default.fileExists(atPath: path + "/Info.plist") && registered }
    var available: Bool { FileManager.default.fileExists(atPath: path + "/Info.plist") }
    var registered: Bool { UserDefaults.standard.object(forKey: "pm." + id) as? Bool ?? (id == "Sileo") }

    static let all = [
        PackageManager(id: "Sileo", path: "/Applications/Sileo.app"),
        PackageManager(id: "Zebra", path: "/var/jb/Applications/Zebra.app"),
    ]

    /// uicache (Procursus) registers or unregisters the app with LaunchServices, so it appears on or leaves the home screen.
    func set(_ on: Bool) -> Bool {
        var pid: pid_t = 0
        let args = ["/var/jb/usr/bin/uicache", on ? "-p" : "-u", path]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        guard posix_spawn(&pid, args[0], nil, nil, &argv, environ) == 0 else { return false }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let ok = status == 0
        if ok { UserDefaults.standard.set(on, forKey: "pm." + id) }
        return ok
    }
}

// MARK: - Themes

struct Theme: Identifiable, Equatable {
    let id: String
    let top: Color
    let bottom: Color
    let accent: Color

    static let all: [Theme] = [
        Theme(id: "Ign1te", top: Color(red: 0.93, green: 0.42, blue: 0.16), bottom: Color(red: 0.42, green: 0.10, blue: 0.20),
              accent: Color(red: 1.0, green: 0.70, blue: 0.30)),
        Theme(id: "Ember", top: Color(red: 0.25, green: 0.56, blue: 0.47), bottom: Color(red: 0.13, green: 0.33, blue: 0.37),
              accent: Color(red: 0.45, green: 0.85, blue: 0.62)),
        Theme(id: "Deep Blue Sky", top: Color(red: 0.20, green: 0.40, blue: 0.80), bottom: Color(red: 0.07, green: 0.12, blue: 0.32),
              accent: Color(red: 0.55, green: 0.75, blue: 1.0)),
        Theme(id: "Blood Sky", top: Color(red: 0.75, green: 0.12, blue: 0.16), bottom: Color(red: 0.22, green: 0.03, blue: 0.08),
              accent: Color(red: 1.0, green: 0.45, blue: 0.45)),
        Theme(id: "Desert Dusk", top: Color(red: 0.86, green: 0.62, blue: 0.40), bottom: Color(red: 0.38, green: 0.22, blue: 0.30),
              accent: Color(red: 1.0, green: 0.85, blue: 0.60)),
    ]
}

// MARK: - App

@main
struct Ign1teApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum Page { case main, settings, theme, credits, managers, choose, ssh, jailbreaking }

final class Model: ObservableObject {
    @Published var page: Page = .main
    @Published var jailbroken = Kernel.injection
    @Published var steps: [String] = []
    @Published var message: String?
    @AppStorage("theme") var themeID = "Ign1te"
    var theme: Theme { Theme.all.first { $0.id == themeID } ?? Theme.all[0] }

    @Published var chosen: Set<String> = Set(PackageManager.all.filter { $0.registered }.map { $0.id })

    func start() {
        if UserDefaults.standard.bool(forKey: "chosePackageManagers") { jailbreak() } else { page = .choose }
    }

    func jailbreak() {
        UserDefaults.standard.set(true, forKey: "chosePackageManagers")
        steps = []
        page = .jailbreaking
        let plan: [(String, () -> Bool)] = [
            ("Checking the kernel…", { Kernel.available }),
            ("Bootstrap in /var/jb…", { FileManager.default.fileExists(atPath: "/var/jb/usr/bin/apt") }),
            ("Installing package managers…", { self.applyManagers() }),
            ("Starting SSH…", { SSH.start() == 0 || true }),
            ("Enabling tweak injection…", { Kernel.request(3) }),
            ("Restarting SpringBoard…", { true }),
        ]
        run(plan, index: 0) { ok in
            if ok {
                self.jailbroken = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { _ = Kernel.request(1) }
            }
        }
    }

    func removeJailbreak() {
        if Kernel.request(4) {
            jailbroken = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { _ = Kernel.request(1) }
        } else {
            message = "The kernel refused (is this the ios-b1lte kernel?)"
        }
    }

    func applyManagers() -> Bool {
        var ok = true
        for pm in PackageManager.all where pm.available && pm.registered != chosen.contains(pm.id) {
            ok = pm.set(chosen.contains(pm.id)) && ok
        }
        objectWillChange.send()
        return ok
    }

    private func run(_ plan: [(String, () -> Bool)], index: Int, done: @escaping (Bool) -> Void) {
        guard index < plan.count else { done(true); return }
        steps.append(plan[index].0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if plan[index].1() {
                self.run(plan, index: index + 1, done: done)
            } else {
                self.steps.append("✕ Failed: " + plan[index].0)
                self.message = "Failed at: " + plan[index].0
                done(false)
            }
        }
    }
}

struct RootView: View {
    @StateObject var model = Model()
    init() { if Kernel.injection { _ = SSH.start() } }

    var body: some View {
        ZStack {
            LinearGradient(colors: [model.theme.top, model.theme.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 70)
                Text("Ign1te")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("iOS 26 · Galaxy S10 (b1lte)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 4)
                Text("Ign1te made for ios-b1lte by homek1llua")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 2)
                Spacer().frame(height: 44)
                card
                Spacer()
                bottom
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var panel: Color { Color.black.opacity(0.28) }

    @ViewBuilder var card: some View {
        VStack(spacing: 0) {
            switch model.page {
            case .main: MainList(model: model)
            case .settings: SettingsList(model: model)
            case .theme: ThemeList(model: model)
            case .credits: CreditsList(model: model)
            case .managers: ManagersList(model: model)
            case .ssh: SSHPage(model: model)
            case .choose: ChooseManagers(model: model)
            case .jailbreaking: Progress(model: model)
            }
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(panel))
    }

    @ViewBuilder var bottom: some View {
        VStack(spacing: 12) {
            if model.jailbroken {
                Button { model.removeJailbreak() } label: {
                    Text("Remove Jailbreak").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 56)
                }
                .foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(panel))
            }
            Button { if !model.jailbroken { model.start() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.jailbroken ? "lock.open" : "flame")
                    Text(model.jailbroken ? "Jailbroken" : "Jailbreak")
                }
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 64)
            }
            .foregroundColor(model.jailbroken ? .white.opacity(0.5) : .white)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(panel))
            .disabled(model.page == .jailbreaking || model.page == .choose)
        }
    }
}

// MARK: - Rows

struct Row: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var chevron = false
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 22, weight: .regular)).frame(width: 28)
                Text(title).font(.system(size: 18, weight: .medium))
                Spacer()
                if let detail { Text(detail).foregroundColor(.white.opacity(0.5)) }
                if chevron { Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)) }
            }
            .foregroundColor(.white.opacity(dimmed ? 0.45 : 1))
            .padding(.horizontal, 24).frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Divide: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 24) }
}

struct Header: View {
    let title: String
    var back: (() -> Void)? = nil
    var body: some View {
        ZStack {
            Text(title).font(.system(size: 19, weight: .semibold)).foregroundColor(.white)
            if let back {
                HStack {
                    Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)) }
                        .foregroundColor(.white)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 24).frame(height: 56)
    }
}

struct MainList: View {
    @ObservedObject var model: Model
    var body: some View {
        Row(icon: "gearshape", title: "Settings", chevron: true) { model.page = .settings }
        Divide()
        Row(icon: "arrow.clockwise", title: "Restart SpringBoard", dimmed: !model.jailbroken) {
            if !Kernel.request(1) { model.message = "The kernel refused the restart" }
        }
        Divide()
        Row(icon: "arrow.triangle.2.circlepath.circle", title: "Reboot Userspace", dimmed: !model.jailbroken) {
            if !Kernel.request(2) { model.message = "The kernel refused the userspace reboot" }
        }
        Divide()
        Row(icon: "info.circle", title: "Credits", chevron: true) { model.page = .credits }
    }
}

struct SettingsList: View {
    @ObservedObject var model: Model
    var body: some View {
        Header(title: "Settings") { model.page = .main }
        Toggle(isOn: Binding(get: { model.jailbroken }, set: { on in
            if Kernel.request(on ? 3 : 4) { model.jailbroken = on } else { model.message = "The kernel refused" }
        })) {
            Text("Tweak Injection").font(.system(size: 18, weight: .medium)).foregroundColor(.white)
        }
        .tint(model.theme.accent)
        .padding(.horizontal, 24).frame(height: 62)
        Divide()
        Row(icon: "shippingbox", title: "Package Managers", detail: model.chosen.sorted().joined(separator: ", "), chevron: true) { model.page = .managers }
        Divide()
        Row(icon: "terminal", title: "SSH", detail: SSH.running ? "On" : "Off", chevron: true) { model.page = .ssh }
        Divide()
        Row(icon: "paintpalette", title: "Theme", detail: model.themeID, chevron: true) { model.page = .theme }
        Divide()
        Text("Tweak injection loads ElleKit into apps and SpringBoard. It takes effect after a SpringBoard restart.")
            .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 24).padding(.vertical, 14)
    }
}

struct ThemeList: View {
    @ObservedObject var model: Model
    var body: some View {
        Header(title: "Theme") { model.page = .settings }
        ForEach(Theme.all) { t in
            Button { model.themeID = t.id; model.objectWillChange.send() } label: {
                HStack {
                    Text(t.id).font(.system(size: 18, weight: .medium))
                    Spacer()
                    if t.id == model.themeID { Image(systemName: "checkmark").foregroundColor(t.accent) }
                }
                .foregroundColor(.white).padding(.horizontal, 24).frame(height: 54).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct CreditsList: View {
    @ObservedObject var model: Model
    let groups: [(String, [String])] = [
        ("PORT", ["homek1llua", "malthiscode"]),
        ("FIRMWARE & GPU", ["Mu-Silicium", "Scion (hackios)", "Mesa / Panfrost"]),
        ("JAILBREAK", ["Procursus", "palera1n bootstrap", "Sileo", "ElleKit"]),
    ]
    var body: some View {
        Header(title: "Ign1te 1.0 - Credits") { model.page = .main }
        ForEach(groups, id: \.0) { g in
            VStack(alignment: .leading, spacing: 8) {
                Text(g.0).font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                ForEach(g.1, id: \.self) { Text($0).font(.system(size: 17, weight: .medium)).foregroundColor(.white.opacity(0.85)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 10)
        }
    }
}

struct Progress: View {
    @ObservedObject var model: Model
    var body: some View {
        Header(title: "Jailbreaking")
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(model.steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 12) {
                    if s.hasPrefix("✕") {
                        Image(systemName: "xmark").foregroundColor(.red)
                    } else if i < model.steps.count - 1 || model.jailbroken {
                        Image(systemName: "checkmark").foregroundColor(model.theme.accent)
                    } else {
                        ProgressView().tint(.white)
                    }
                    Text(s).foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(.horizontal, 24).padding(.bottom, 16)
        if model.message != nil || model.steps.last?.hasPrefix("✕") == true {
            Row(icon: "chevron.left", title: "Back") { model.page = .main }
        }
    }
}

// MARK: - Package manager pages

struct ManagerTile: View {
    @ObservedObject var model: Model
    let pm: PackageManager
    var body: some View {
        Button {
            if model.chosen.contains(pm.id) { model.chosen.remove(pm.id) } else { model.chosen.insert(pm.id) }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)).frame(width: 64, height: 64)
                    Image(systemName: pm.id == "Sileo" ? "cube.box.fill" : "shippingbox.fill").font(.system(size: 28)).foregroundColor(.white)
                }
                Text(pm.id).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                Image(systemName: model.chosen.contains(pm.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(model.chosen.contains(pm.id) ? model.theme.accent : .white.opacity(0.5))
                if !pm.available { Text("not in this build").font(.system(size: 11)).foregroundColor(.white.opacity(0.4)) }
            }
            .opacity(pm.available ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!pm.available)
    }
}

struct ChooseManagers: View {
    @ObservedObject var model: Model
    var body: some View {
        Header(title: "Jailbreak") { model.page = .main }
        Text("Select package managers").font(.system(size: 17, weight: .semibold)).foregroundColor(.white).padding(.top, 8)
        HStack(spacing: 36) { ForEach(PackageManager.all) { ManagerTile(model: model, pm: $0) } }.padding(.vertical, 18)
        Text("If you are unsure which one to select, use Sileo").font(.system(size: 12)).foregroundColor(.white.opacity(0.45))
        Button { model.jailbreak() } label: {
            HStack { Image(systemName: "arrow.right"); Text("Continue") }
                .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(model.chosen.isEmpty ? 0.06 : 0.14)))
        }
        .disabled(model.chosen.isEmpty)
        .padding(24)
    }
}

struct ManagersList: View {
    @ObservedObject var model: Model
    var body: some View {
        Header(title: "Package Managers") { model.page = .settings }
        HStack(spacing: 36) { ForEach(PackageManager.all) { ManagerTile(model: model, pm: $0) } }.padding(.vertical, 18)
        Button {
            if !model.applyManagers() { model.message = "uicache failed for one of them" }
        } label: {
            Text("Apply").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.14)))
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }
}

// MARK: - SSH page

struct SSHPage: View {
    @ObservedObject var model: Model
    @State var tick = 0
    var body: some View {
        Header(title: "SSH") { model.page = .settings }
        VStack(alignment: .leading, spacing: 10) {
            Text(SSH.running ? "Running" : "Not running").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Text("ssh root@\(SSH.address)").font(.system(size: 15, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                .textSelection(.enabled)
            Text("Key login only (the b1l_ssh_key file on your PC).").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            Text(SSH.log).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.6)).padding(.top, 6)
            Text("\(tick)").hidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 10)
        Button {
            let r = SSH.start()
            if r != 0 { model.message = "sshd did not start (status \(r))" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick += 1 }
        } label: {
            Text(SSH.running ? "Restart check" : "Start SSH").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.14)))
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }
}
