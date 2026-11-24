import AppKit
import MeetingAgendaClockCore
import Observation
import SwiftUI

/// The app's state: the saved agendas, the run if one is going, and which agenda is selected.
/// Saves to the data folder on every change.
@MainActor
@Observable
final class AppModel {
    var agendas: [Agenda] {
        didSet { if persists { saveAgendas() } }
    }

    var run: Run? {
        didSet {
            if persists { saveRun() }
            runChanged()
        }
    }

    var selection: Agenda.ID?
    /// The last save or load that failed, shown in the Agendas window.
    var problem: String?
    /// Refreshed once a second while a run is going, so the menu bar menu's text stays current.
    /// Only for redrawing: every number is computed from the run and the time, never counted.
    private(set) var now = Date()

    let store: AgendaStore
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var refresh: Timer?
    @ObservationIgnored let edgeLine = EdgeLineController()
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    init(store: AgendaStore, defaults: UserDefaults = .standard, agendas: [Agenda], run: Run?, persists: Bool) {
        self.store = store
        self.defaults = defaults
        self.persists = persists
        self.agendas = agendas
        self.run = run
        selection = run?.agendaID ?? agendas.first?.id
    }

    /// The model the app runs with, reading the data folder. A first launch gets one sample agenda.
    static func live() -> AppModel {
        let store = AgendaStore(folder: AppPaths.dataFolder())
        var problem: String?
        var agendas: [Agenda]
        do {
            agendas = try store.loadAgendas() ?? [SampleAgendas.weeklyDemo]
        } catch {
            agendas = []
            problem = "Could not read \(store.agendasFile.path): \(error.localizedDescription)"
        }
        let run = try? store.loadRun()
        let model = AppModel(store: store, agendas: agendas, run: run, persists: problem == nil)
        model.problem = problem
        model.startObserving()
        return model
    }

    /// Starts watching the preferences for the edge line switch, and shows the line if a run
    /// survived the last quit.
    func startObserving() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEdgeLine() }
        }
        runChanged()
    }

    // MARK: - Agendas

    func index(of id: Agenda.ID?) -> Int? {
        agendas.firstIndex { $0.id == id }
    }

    var selectedAgenda: Agenda? {
        index(of: selection).map { agendas[$0] }
    }

    func addAgenda() {
        var agenda = Agenda.blank(endRule: GeneralPreference.defaultEndRule(defaults))
        let names = Set(agendas.map(\.name))
        var number = 2
        while names.contains(agenda.name) {
            agenda.name = "New Agenda \(number)"
            number += 1
        }
        agendas.append(agenda)
        selection = agenda.id
    }

    func deleteAgenda(_ id: Agenda.ID) {
        guard run?.agendaID != id, let index = index(of: id) else { return }
        agendas.remove(at: index)
        if selection == id { selection = agendas.first?.id }
    }

    // MARK: - Running

    func isRunning(_ id: Agenda.ID) -> Bool { run?.agendaID == id }

    /// Whether `id` can start now: it has time in it and nothing else is running.
    func canStart(_ id: Agenda.ID) -> Bool {
        run == nil && (index(of: id).map { agendas[$0].canStart } ?? false)
    }

    /// Starts `id` now. Returns whether it started, so the caller can open the clock window.
    @discardableResult
    func start(_ id: Agenda.ID, at date: Date = Date()) -> Bool {
        guard canStart(id), let index = index(of: id) else { return false }
        run = Run.start(agendas[index], at: date)
        selection = id
        return true
    }

    func perform(_ kind: RunEvent.Kind, at date: Date = Date()) {
        guard var run else { return }
        if run.record(kind, at: date) { self.run = run }
    }

    func allows(_ kind: RunEvent.Kind) -> Bool {
        run?.allows(kind, at: Date()) ?? false
    }

    func endRun() {
        run = nil
    }

    func state(at date: Date) -> ClockState? {
        run.map { ClockEngine.state(for: $0, at: date) }
    }

    var opensClockWindowOnStart: Bool { GeneralPreference.opensClockWindowOnStart(defaults) }

    // MARK: - Side effects

    private func runChanged() {
        refresh?.invalidate()
        refresh = nil
        now = Date()
        if run != nil {
            refresh = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.now = Date() }
            }
        }
        updateEdgeLine()
    }

    private func updateEdgeLine() {
        guard persists else { return }
        edgeLine.update(run: run, enabled: Experiment.edgeLine.isOn(defaults))
    }

    private func saveAgendas() {
        do {
            try store.save(agendas)
        } catch {
            problem = "Could not save the agendas: \(error.localizedDescription)"
        }
    }

    private func saveRun() {
        do {
            try store.save(run)
        } catch {
            problem = "Could not save the run: \(error.localizedDescription)"
        }
    }
}
