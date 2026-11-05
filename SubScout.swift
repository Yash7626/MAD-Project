import SwiftUI
import Charts
import Combine
import UserNotifications

// MARK: - App entry

@main
struct SubScoutApp: App {
    @StateObject private var store = SubscriptionStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(store)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
                NotificationManager.requestAuthorization()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.refreshAll() }
            }
        }
    }
}

// MARK: - Theme

enum Theme {
    static let bgTop = Color(red: 0.05, green: 0.05, blue: 0.10)
    static let bgBottom = Color(red: 0.09, green: 0.07, blue: 0.16)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.00)
    static let teal = Color(red: 0.25, green: 0.85, blue: 0.82)
    static let gold = Color(red: 0.96, green: 0.80, blue: 0.46)
    static let mint = Color(red: 0.35, green: 0.92, blue: 0.72)
    static let rose = Color(red: 1.00, green: 0.38, blue: 0.48)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.30)

    static let accent = LinearGradient(colors: [violet, teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldText = LinearGradient(colors: [Color.white, gold],
                                         startPoint: .leading, endPoint: .trailing)
    static let border = LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Theme.violet.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -140, y: -280)
            Circle()
                .fill(Theme.teal.opacity(0.22))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 160, y: 120)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Models

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var shortTitle: String {
        switch self {
        case .weekly: return "/wk"
        case .monthly: return "/mo"
        case .quarterly: return "/qtr"
        case .yearly: return "/yr"
        }
    }

    var monthlyFactor: Double {
        switch self {
        case .weekly: return 52.0 / 12.0
        case .monthly: return 1
        case .quarterly: return 1.0 / 3.0
        case .yearly: return 1.0 / 12.0
        }
    }

    func next(after date: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly: return cal.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly: return cal.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

enum SubCategory: String, Codable, CaseIterable, Identifiable {
    case entertainment, music, productivity, cloud, news, fitness, education, finance, utilities, other

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .entertainment: return "play.tv.fill"
        case .music: return "music.note"
        case .productivity: return "briefcase.fill"
        case .cloud: return "icloud.fill"
        case .news: return "newspaper.fill"
        case .fitness: return "figure.run"
        case .education: return "book.fill"
        case .finance: return "indianrupeesign.circle.fill"
        case .utilities: return "bolt.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .entertainment: return Color(red: 1.00, green: 0.42, blue: 0.62)
        case .music: return Color(red: 0.35, green: 0.92, blue: 0.60)
        case .productivity: return Color(red: 0.42, green: 0.65, blue: 1.00)
        case .cloud: return Color(red: 0.40, green: 0.88, blue: 1.00)
        case .news: return Color(red: 1.00, green: 0.66, blue: 0.30)
        case .fitness: return Color(red: 1.00, green: 0.42, blue: 0.40)
        case .education: return Color(red: 0.72, green: 0.52, blue: 1.00)
        case .finance: return Color(red: 0.96, green: 0.80, blue: 0.46)
        case .utilities: return Color(red: 1.00, green: 0.90, blue: 0.40)
        case .other: return Color(red: 0.62, green: 0.66, blue: 0.76)
        }
    }
}

struct Subscription: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var currency: String = "INR"
    var cycle: BillingCycle = .monthly
    var nextRenewal: Date
    var category: SubCategory = .other
    var remindDaysBefore: Int = 2
    var isActive: Bool = true
    var notes: String = ""

    var monthlyCost: Double { amount * cycle.monthlyFactor }

    var daysUntilRenewal: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: nextRenewal)).day ?? 0
    }

    /// The moment the reminder notification is scheduled for (9:00 AM).
    var reminderDate: Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: -remindDaysBefore, to: nextRenewal) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps)
    }

    mutating func rollForward() {
        let today = Calendar.current.startOfDay(for: Date())
        var count = 0
        while nextRenewal < today && count < 500 {
            nextRenewal = cycle.next(after: nextRenewal)
            count += 1
        }
    }
}

// MARK: - Notifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(_ sub: Subscription, occurrences: Int = 4) {
        cancel(sub)
        guard sub.isActive else { return }

        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        var renewal = sub.nextRenewal

        for i in 0..<occurrences {
            if let remindDay = cal.date(byAdding: .day, value: -sub.remindDaysBefore, to: renewal) {
                var comps = cal.dateComponents([.year, .month, .day], from: remindDay)
                comps.hour = 9
                comps.minute = 0

                if let fireDate = cal.date(from: comps), fireDate > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = "\(sub.name) renews soon"
                    let amount = sub.amount.formatted(.currency(code: sub.currency))
                    let when = sub.remindDaysBefore == 0 ? "today" : "in \(sub.remindDaysBefore) day(s)"
                    content.body = "\(amount) will be auto-debited \(when). Cancel now if you no longer need it."
                    content.sound = .default

                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: "\(sub.id)-\(i)",
                                                     content: content,
                                                     trigger: trigger))
                }
            }
            renewal = sub.cycle.next(after: renewal)
        }
    }

    static func cancel(_ sub: Subscription) {
        let ids = (0..<8).map { "\(sub.id)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Store

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var subscriptions: [Subscription] = []

    private let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("subscriptions.json")
    }()

    init() {
        load()
        refreshAll()
    }

    func add(_ sub: Subscription) {
        subscriptions.append(sub)
        commit(sub)
    }

    func update(_ sub: Subscription) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx] = sub
        commit(sub)
    }

    func delete(_ sub: Subscription) {
        NotificationManager.cancel(sub)
        subscriptions.removeAll { $0.id == sub.id }
        save()
    }

    func markPaid(_ sub: Subscription) {
        var s = sub
        s.nextRenewal = s.cycle.next(after: s.nextRenewal)
        update(s)
    }

    func toggleActive(_ sub: Subscription) {
        var s = sub
        s.isActive.toggle()
        update(s)
    }

    private func commit(_ sub: Subscription) {
        NotificationManager.schedule(sub)
        save()
    }

    func refreshAll() {
        for i in subscriptions.indices {
            subscriptions[i].rollForward()
            NotificationManager.schedule(subscriptions[i])
        }
        save()
    }

    var active: [Subscription] { subscriptions.filter(\.isActive) }
    var monthlyTotal: Double { active.reduce(0) { $0 + $1.monthlyCost } }
    var yearlyTotal: Double { monthlyTotal * 12 }

    func dueWithin(days: Int) -> [Subscription] {
        active.sorted { $0.nextRenewal < $1.nextRenewal }
              .filter { $0.daysUntilRenewal <= days }
    }

    func amountDue(within days: Int) -> Double {
        dueWithin(days: days).reduce(0) { $0 + $1.amount }
    }

    var nextUp: Subscription? {
        active.sorted { $0.nextRenewal < $1.nextRenewal }.first
    }

    var topExpensive: [Subscription] {
        Array(active.sorted { $0.monthlyCost > $1.monthlyCost }.prefix(3))
    }

    var spendByCategory: [(category: SubCategory, monthly: Double)] {
        Dictionary(grouping: active, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.monthlyCost }) }
            .sorted { $0.1 > $1.1 }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Subscription].self, from: data) else { return }
        subscriptions = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Shared helpers

private func money(_ value: Double, _ code: String = "INR") -> String {
    value.formatted(.currency(code: code).precision(.fractionLength(0...2)))
}

private func dueText(_ days: Int) -> String {
    switch days {
    case ..<0: return "Overdue"
    case 0: return "Today"
    case 1: return "Tomorrow"
    default: return "in \(days) days"
    }
}

private func dueColor(_ days: Int) -> Color {
    days <= 1 ? Theme.rose : (days <= 7 ? Theme.amber : Theme.mint)
}

private extension View {
    func glass(_ radius: CGFloat = 24, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

struct IconBadge: View {
    let category: SubCategory
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(category.color.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(category.color.opacity(0.35), lineWidth: 1)
            )
    }
}

struct DuePill: View {
    let days: Int

    var body: some View {
        Text(dueText(days))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(dueColor(days))
            .background(dueColor(days).opacity(0.16), in: Capsule())
    }
}

/// The SubScout app icon, drawn in code so it shows inside the app with no image file.
struct RadarLogo: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.10),
                                    Color(red: 0.12, green: 0.08, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Theme.violet.opacity(0.55)).frame(width: size * 0.7)
                .blur(radius: size * 0.2).offset(x: -size * 0.2, y: -size * 0.2)
            Circle().fill(Theme.teal.opacity(0.35)).frame(width: size * 0.6)
                .blur(radius: size * 0.2).offset(x: size * 0.25, y: size * 0.25)

            Circle().stroke(Theme.violet.opacity(0.6), lineWidth: size * 0.022)
                .frame(width: size * 0.76)
            Circle().stroke(Color(red: 0.45, green: 0.62, blue: 0.95).opacity(0.8), lineWidth: size * 0.024)
                .frame(width: size * 0.57)
            Circle().stroke(Theme.teal, lineWidth: size * 0.026)
                .frame(width: size * 0.37)

            Circle().fill(Color.white).frame(width: size * 0.125)

            Circle().fill(Theme.gold)
                .frame(width: size * 0.068)
                .offset(x: size * 0.285 * CGFloat(cos(-55.0 * .pi / 180)),
                        y: size * 0.285 * CGFloat(sin(-55.0 * .pi / 180)))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Splash screen

struct SplashView: View {
    @State private var appear = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Theme.violet.opacity(0.45), lineWidth: 2)
                        .frame(width: 170, height: 170)
                        .scaleEffect(pulse ? 1.7 : 0.9)
                        .opacity(pulse ? 0 : 0.9)
                    Circle()
                        .stroke(Theme.teal.opacity(0.40), lineWidth: 2)
                        .frame(width: 170, height: 170)
                        .scaleEffect(pulse ? 2.2 : 0.9)
                        .opacity(pulse ? 0 : 0.7)

                    RadarLogo(size: 130)
                        .shadow(color: Theme.violet.opacity(0.55), radius: 30)
                        .scaleEffect(appear ? 1 : 0.55)
                        .opacity(appear ? 1 : 0)
                }
                .frame(height: 260)

                Text("SubScout")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.goldText)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                Text("Never miss a renewal")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                Spacer()

                VStack(spacing: 5) {
                    Text("CREATED BY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(.secondary)
                    Text("Yash")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 54)
                .opacity(appear ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { appear = true }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - Root + floating tab bar

enum AppTab: Int, CaseIterable, Identifiable {
    case home, subs, insights

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .subs: return "Subs"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .subs: return "creditcard.fill"
        case .insights: return "chart.pie.fill"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showingNew = false

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(selection: $tab, onAdd: { showingNew = true })
        }
        .sheet(isPresented: $showingNew) {
            SubscriptionEditor(subscription: Subscription(name: "", amount: 0, nextRenewal: Date()), isNew: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home: HomeView(onAdd: { showingNew = true })
        case .subs: SubscriptionListView(onAdd: { showingNew = true })
        case .insights: InsightsView()
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: Circle())
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: 480)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                Text(tab.title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? Color.white.opacity(0.12) : Color.clear, in: Capsule())
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: SubscriptionStore
    let onAdd: () -> Void

    @State private var showYearly = false
    @State private var showingAlerts = false
    @State private var editing: Subscription?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var urgentCount: Int { store.dueWithin(days: 3).count }

    private var groups: [(title: String, items: [Subscription])] {
        let list = store.active.sorted { $0.nextRenewal < $1.nextRenewal }
        var result: [(title: String, items: [Subscription])] = []

        let today = list.filter { $0.daysUntilRenewal <= 0 }
        let week = list.filter { $0.daysUntilRenewal >= 1 && $0.daysUntilRenewal <= 7 }
        let month = list.filter { $0.daysUntilRenewal >= 8 && $0.daysUntilRenewal <= 30 }
        let later = list.filter { $0.daysUntilRenewal > 30 }

        if !today.isEmpty { result.append((title: "Today", items: today)) }
        if !week.isEmpty { result.append((title: "This week", items: week)) }
        if !month.isEmpty { result.append((title: "This month", items: month)) }
        if !later.isEmpty { result.append((title: "Later", items: later)) }
        return result
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header

                HeroCard(monthly: store.monthlyTotal,
                         yearly: store.yearlyTotal,
                         count: store.active.count,
                         weekDue: store.amountDue(within: 7),
                         perDay: store.monthlyTotal / 30,
                         next: store.nextUp,
                         showYearly: $showYearly)

                if store.subscriptions.isEmpty {
                    emptyState
                } else {
                    comingUp
                    timeline
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { sub in
            SubscriptionEditor(subscription: sub, isNew: false)
        }
        .sheet(isPresented: $showingAlerts) {
            AlertsView()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RadarLogo(size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("SubScout")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            Spacer()

            Button {
                showingAlerts = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))

                    if urgentCount > 0 {
                        Text("\(urgentCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 19, height: 19)
                            .background(Theme.rose, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var comingUp: some View {
        let soon = store.dueWithin(days: 14)
        if !soon.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coming up").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(soon) { sub in
                            UpcomingCard(sub: sub)
                                .onTapGesture { editing = sub }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Timeline").font(.title3.weight(.bold))

            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    ForEach(group.items) { sub in
                        CompactRow(sub: sub)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = sub }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)
            Text("Add your first subscription")
                .font(.headline)
            Text("Track what renews and when, and get reminded before money leaves your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label("Add subscription", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.black)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .glass(28, padding: 28)
    }
}

struct HeroCard: View {
    let monthly: Double
    let yearly: Double
    let count: Int
    let weekDue: Double
    let perDay: Double
    let next: Subscription?
    @Binding var showYearly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            topRow
            totalBlock
            Divider().overlay(Color.white.opacity(0.12))
            statsRow
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.white.opacity(0.06)
                Circle().fill(Theme.violet.opacity(0.45)).frame(width: 220).blur(radius: 60).offset(x: 130, y: -70)
                Circle().fill(Theme.teal.opacity(0.30)).frame(width: 180).blur(radius: 60).offset(x: -140, y: 90)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .animation(.snappy, value: showYearly)
    }

    private var topRow: some View {
        HStack {
            HStack(spacing: 0) {
                toggleButton("Monthly", selected: !showYearly) { showYearly = false }
                toggleButton("Yearly", selected: showYearly) { showYearly = true }
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())

            Spacer()

            Label("\(count) active", systemImage: "checkmark.seal.fill")
                .font(.caption.bold())
                .foregroundStyle(Theme.mint)
        }
    }

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showYearly ? "Total per year" : "Total per month")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(money(showYearly ? yearly : monthly))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.goldText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            miniStat("Next 7 days", money(weekDue))
            miniStat("Per day", money(perDay))
            miniStat("Next charge", next?.name ?? "None")
        }
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
                .background(selected ? Color.white : Color.clear, in: Capsule())
        }
    }
}

struct UpcomingCard: View {
    let sub: Subscription

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconBadge(category: sub.category, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(sub.name).font(.headline).lineLimit(1)
                Text(money(sub.amount, sub.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            DuePill(days: sub.daysUntilRenewal)
        }
        .frame(width: 140, alignment: .leading)
        .glass(24)
    }
}

struct CompactRow: View {
    let sub: Subscription

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(category: sub.category, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(sub.name).font(.headline).lineLimit(1)
                Text(sub.nextRenewal.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(money(sub.amount, sub.currency))
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                DuePill(days: sub.daysUntilRenewal)
            }
        }
        .glass(22)
    }
}

// MARK: - Alerts (bell screen)

struct AlertsView: View {
    @EnvironmentObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var message = ""

    private var isAllowed: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private var urgent: [Subscription] {
        store.dueWithin(days: 3)
    }

    private var upcoming: [Subscription] {
        let list = store.active
            .filter { $0.daysUntilRenewal > 3 }
            .sorted { $0.nextRenewal < $1.nextRenewal }
        return Array(list.prefix(20))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    topBar

                    if !isAllowed {
                        permissionBanner
                    }

                    needsAttention
                    upcomingReminders
                    testSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await refreshStatus() }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(urgent.count) need attention")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Alerts")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 20)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.title3)
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Phone alerts are off").font(.subheadline.weight(.bold))
                Text("Turn them on to get a notification before each auto-debit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(status == .denied ? "Settings" : "Enable") {
                Task { await enableNotifications() }
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.black)
            .background(Theme.amber, in: Capsule())
        }
        .glass(20)
    }

    private var needsAttention: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needs attention").font(.title3.weight(.bold))

            if urgent.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're all clear").font(.headline)
                        Text("Nothing is being charged in the next 3 days.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .glass(22)
            } else {
                ForEach(urgent) { sub in
                    urgentCard(sub)
                }
            }
        }
    }

    private func urgentCard(_ sub: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(category: sub.category, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.name).font(.headline)
                    Text("\(money(sub.amount, sub.currency)) auto-debit \(dueText(sub.daysUntilRenewal).lowercased())")
                        .font(.subheadline)
                        .foregroundStyle(dueColor(sub.daysUntilRenewal))
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    store.markPaid(sub)
                } label: {
                    Label("Mark paid", systemImage: "checkmark")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(Color.black)
                        .background(Theme.mint, in: Capsule())
                }
                Button {
                    store.toggleActive(sub)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .glass(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(dueColor(sub.daysUntilRenewal).opacity(0.5), lineWidth: 1)
        )
    }

    private var upcomingReminders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scheduled reminders").font(.title3.weight(.bold))

            if upcoming.isEmpty {
                Text("No other reminders yet. Add subscriptions and they will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(22)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcoming) { sub in
                        reminderRow(sub)
                        if sub.id != upcoming.last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .glass(22)
            }
        }
    }

    private func reminderRow(_ sub: Subscription) -> some View {
        HStack(spacing: 12) {
            IconBadge(category: sub.category, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name).font(.subheadline.weight(.semibold))
                Text(reminderText(sub))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(money(sub.amount, sub.currency))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
    }

    private func reminderText(_ sub: Subscription) -> String {
        guard let date = sub.reminderDate else { return "Renews \(dueText(sub.daysUntilRenewal))" }
        if date > Date() {
            return "Reminder on \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Renews \(dueText(sub.daysUntilRenewal))"
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await sendTest() }
            } label: {
                Label("Send a test alert to my phone", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    private func enableNotifications() async {
        if status == .notDetermined {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func sendTest() async {
        if status == .notDetermined {
            await enableNotifications()
        }
        guard isAllowed else {
            message = "Phone alerts are blocked. Tap Settings above and allow notifications for SubScout."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "SubScout test"
        content.body = "Alerts are working. Renewal reminders will look like this."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "subscout-test-\(UUID().uuidString)",
                                            content: content,
                                            trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            message = "Sent. A banner should appear in about 5 seconds."
        } catch {
            message = "Could not send: \(error.localizedDescription)"
        }
    }
}

// MARK: - Subscriptions

enum SubFilter: String, CaseIterable, Identifiable {
    case all = "All", active = "Active", paused = "Paused"
    var id: String { rawValue }
}

struct SubscriptionListView: View {
    @EnvironmentObject var store: SubscriptionStore
    let onAdd: () -> Void

    @State private var editing: Subscription?
    @State private var query = ""
    @State private var filter: SubFilter = .all
    @State private var pendingDelete: Subscription?

    private var filtered: [Subscription] {
        store.subscriptions
            .filter { sub in
                switch filter {
                case .all: return true
                case .active: return sub.isActive
                case .paused: return !sub.isActive
                }
            }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.nextRenewal < $1.nextRenewal }
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ScreenHeader(title: "Subscriptions",
                             subtitle: "\(store.subscriptions.count) total · \(money(store.monthlyTotal)) / month")

                searchBar
                filterChips

                if store.subscriptions.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { sub in
                            card(sub)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { sub in
            SubscriptionEditor(subscription: sub, isNew: false)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "subscription")?",
            isPresented: deleteDialogShown,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let sub = pendingDelete { store.delete(sub) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This also removes its reminders. This cannot be undone.")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search subscriptions", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(SubFilter.allCases) { item in
                let selected = filter == item
                Button {
                    withAnimation(.snappy) { filter = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
                        .background(selected ? Color.white : Color.white.opacity(0.08), in: Capsule())
                }
            }
            Spacer()
        }
    }

    private func card(_ sub: Subscription) -> some View {
        HStack(spacing: 14) {
            IconBadge(category: sub.category)

            VStack(alignment: .leading, spacing: 5) {
                Text(sub.name).font(.headline).lineLimit(1)
                if sub.isActive {
                    HStack(spacing: 6) {
                        DuePill(days: sub.daysUntilRenewal)
                        Text(sub.nextRenewal.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Paused").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(money(sub.amount, sub.currency))
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(sub.cycle.shortTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button { editing = sub } label: { Label("Edit", systemImage: "pencil") }
                Button { store.markPaid(sub) } label: { Label("Mark as paid", systemImage: "checkmark.circle") }
                Button { store.toggleActive(sub) } label: {
                    Label(sub.isActive ? "Pause" : "Resume",
                          systemImage: sub.isActive ? "pause.circle" : "play.circle")
                }
                Button(role: .destructive) { pendingDelete = sub } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
        }
        .glass(24)
        .opacity(sub.isActive ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { editing = sub }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No subscriptions yet").font(.headline)
            Button(action: onAdd) {
                Label("Add subscription", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.black)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .glass(28, padding: 28)
    }
}

// MARK: - Insights

struct InsightsView: View {
    @EnvironmentObject var store: SubscriptionStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                ScreenHeader(title: "Insights", subtitle: "See where your money goes")

                if store.spendByCategory.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No data yet").font(.headline)
                        Text("Add subscriptions to see your spending breakdown.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .glass(28, padding: 28)
                } else {
                    breakdown
                    topSpenders
                    tip
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var breakdown: some View {
        VStack(spacing: 18) {
            Chart(store.spendByCategory, id: \.category) { item in
                SectorMark(angle: .value("Monthly", item.monthly),
                           innerRadius: .ratio(0.66),
                           angularInset: 2)
                    .cornerRadius(6)
                    .foregroundStyle(item.category.color)
            }
            .frame(height: 220)
            .overlay {
                VStack(spacing: 2) {
                    Text("per month").font(.caption).foregroundStyle(.secondary)
                    Text(money(store.monthlyTotal))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.goldText)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(.horizontal, 64)
            }

            VStack(spacing: 12) {
                ForEach(store.spendByCategory, id: \.category) { item in
                    legendRow(item.category, item.monthly)
                }
            }
        }
        .glass(28, padding: 20)
    }

    private func legendRow(_ category: SubCategory, _ monthly: Double) -> some View {
        let pct = store.monthlyTotal > 0 ? Int((monthly / store.monthlyTotal * 100).rounded()) : 0
        return HStack(spacing: 10) {
            Circle().fill(category.color).frame(width: 10, height: 10)
            Text(category.title).font(.subheadline)
            Spacer()
            Text(money(monthly)).font(.subheadline.weight(.semibold))
            Text("\(pct)%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var topSpenders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Biggest expenses").font(.title3.weight(.bold))
            VStack(spacing: 14) {
                ForEach(Array(store.topExpensive.enumerated()), id: \.element.id) { index, sub in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(Theme.gold)
                            .frame(width: 20)
                        IconBadge(category: sub.category, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name).font(.headline).lineLimit(1)
                            Text("\(money(sub.monthlyCost)) a month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(money(sub.monthlyCost * 12))/yr")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .glass(24, padding: 18)
        }
    }

    @ViewBuilder
    private var tip: some View {
        if let top = store.topExpensive.first {
            HStack(spacing: 14) {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Savings tip").font(.headline)
                    Text("\(top.name) is your biggest expense. Cancelling it would save \(money(top.monthlyCost * 12)) a year.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .glass(24)
        }
    }
}

// MARK: - Editor

struct SubscriptionEditor: View {
    @EnvironmentObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State var subscription: Subscription
    let isNew: Bool
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name (e.g. Netflix)", text: $subscription.name)
                    TextField("Amount", value: $subscription.amount, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Billing cycle", selection: $subscription.cycle) {
                        ForEach(BillingCycle.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Next renewal", selection: $subscription.nextRenewal, displayedComponents: .date)
                    Picker("Category", selection: $subscription.category) {
                        ForEach(SubCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Reminder") {
                    Stepper("Remind \(subscription.remindDaysBefore) day(s) before",
                            value: $subscription.remindDaysBefore, in: 0...14)
                    Toggle("Active", isOn: $subscription.isActive)
                }
                Section("Notes") {
                    TextField("Plan, account email, cancel link…", text: $subscription.notes, axis: .vertical)
                }
                if !isNew {
                    Section {
                        Button {
                            store.markPaid(subscription)
                            dismiss()
                        } label: {
                            Label("Mark as paid (advance to next cycle)", systemImage: "checkmark.circle")
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete subscription", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(isNew ? "New Subscription" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew { store.add(subscription) } else { store.update(subscription) }
                        dismiss()
                    }
                    .disabled(subscription.name.trimmingCharacters(in: .whitespaces).isEmpty || subscription.amount <= 0)
                }
            }
            .confirmationDialog("Delete \(subscription.name)?",
                                isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(subscription)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This also removes its reminders. This cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
