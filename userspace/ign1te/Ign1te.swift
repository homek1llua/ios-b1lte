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

enum Page { case main, settings, theme, credits, jailbreaking }

final class Model: ObservableObject {
    @Published var page: Page = .main
    @Published var jailbroken = Kernel.injection
    @Published var steps: [String] = []
    @Published var message: String?
    @AppStorage("theme") var themeID = "Ign1te"
    var theme: Theme { Theme.all.first { $0.id == themeID } ?? Theme.all[0] }

    func jailbreak() {
        steps = []
        page = .jailbreaking
        let plan: [(String, () -> Bool)] = [
            ("Checking the kernel…", { Kernel.available }),
            ("Bootstrap in /var/jb…", { FileManager.default.fileExists(atPath: "/var/jb/usr/bin/apt") }),
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
            Button { if !model.jailbroken { model.jailbreak() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.jailbroken ? "lock.open" : "flame")
                    Text(model.jailbroken ? "Jailbroken" : "Jailbreak")
                }
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 64)
            }
            .foregroundColor(model.jailbroken ? .white.opacity(0.5) : .white)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(panel))
            .disabled(model.page == .jailbreaking)
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
