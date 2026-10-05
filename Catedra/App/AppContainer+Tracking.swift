import Foundation
import AppKit

/// Wiring of the phase 10 features: change detector, focus timer, weekly summary and the new-activity autopilot.
extension AppContainer {
    func wireTracking() {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        sync.onSyncSucceeded = { [weak self] _ in
            guard let self else { return }
            let snapshot = workspace.snapshot
            await changes.process(snapshot: snapshot, root: workspace.root)
            autopilot.process(activities: snapshot.activities)
        }

        autopilot.isEnabled = { [weak self] in self?.settings.autopilotApplies(toCourse: $0.courseFolderName) ?? false }
        autopilot.limits = { [weak self] in AutopilotLimits(maxConcurrent: 1, dailyCap: self?.settings.autopilotDailyCap ?? 3) }
        autopilot.stateOf = { [weak self] in self?.workspace.state(of: $0) ?? .pending }
        autopilot.activityLookup = { [weak self] in self?.workspace.activity(id: $0) }
        autopilot.launch = { [weak self] activity, recipe in
            guard let self else { return nil }
            let scope = AgentScope.activity(activity)
            let prompt = RecipeCatalog.render(recipe, scope: scope, activities: [], formatDate: Formatters.due)
            agents.start(scope: scope, prompt: prompt, recipe: recipe, options: settings.defaultOptions(for: settings.agentProvider))
            return agents.runs(in: scope.id).first { $0.isRunning }?.id
        }
        agents.onRunFinished = { [weak self] run in
            self?.autopilot.runFinished(runID: run.id, succeeded: run.status == .succeeded)
        }

        weekly.isEnabled = { [weak self] in self?.settings.weeklySummaryEnabled ?? false }
        weekly.digest = { [weak self] now in
            guard let self else { return WeeklyDigestBuilder.build(now: now, activities: [], isOpen: { _ in true }, grades: [], studyBlocks: [], cardsDue: 0) }
            return WeeklyDigestBuilder.build(now: now, activities: workspace.snapshot.activities,
                                             isOpen: { self.workspace.state(of: $0, now: now) != .submitted },
                                             grades: gradeEntries(), studyBlocks: planner.blocks,
                                             cardsDue: review.todayCount(today: ReviewDay(date: now)))
        }
        weekly.agent = { [weak self] in
            guard let self else { return nil }
            let provider = settings.summaryProvider
            guard let executable = settings.resolvedPath(for: provider) else { return nil }
            return (provider, executable, settings.defaultOptions(for: provider))
        }

        guard !underTest else { return }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.weekly.checkIfDue() }
        }
    }

    /// Loads the app-owned state of the phase 10 features; call once at launch before the first sync result.
    func loadTrackingState() {
        changes.load()
        focus.load()
        weekly.load()
        autopilot.load()
    }

    /// Graded items from the activities and the grade reports, for the weekly digest.
    func gradeEntries() -> [GradeEntry] {
        let snapshot = workspace.snapshot
        var entries = snapshot.activities.filter(\.hasGrade).map {
            GradeEntry(name: $0.name, courseName: $0.courseName, grade: $0.grade, gradedAt: $0.gradedAt)
        }
        for report in snapshot.gradeReports {
            var courseName = "Curso \(report.courseId)"
            if let folder = GradeCourseResolver.folder(for: report, activities: snapshot.activities, events: snapshot.calendarEvents,
                                                       courses: snapshot.courses),
               let course = snapshot.courses.first(where: { $0.folderName == folder }) { courseName = course.name }
            for item in report.items where GradeRules.isGradeable(item) && item.gradeRaw != nil {
                let text = item.gradeFormatted.trimmingCharacters(in: .whitespaces)
                entries.append(GradeEntry(name: item.name, courseName: courseName,
                                          grade: text.isEmpty || text == "-" ? item.gradeRaw.map(GradeFormat.points) ?? "" : text,
                                          gradedAt: item.gradedAt))
            }
        }
        return entries
    }
}

/// Wiring of the desktop widget: the snapshot builder reads the observable models, so any change in them refreshes it.
extension AppContainer {
    func wireWidget() {
        widget = WidgetSyncModel { [weak self] now in
            guard let self else { return WidgetSnapshotBuilder.build(now: now, candidates: [], cardsDue: 0, focus: nil) }
            let candidates = workspace.snapshot.activities.map { activity in
                let course = workspace.course(for: activity)
                return WidgetSnapshotBuilder.Candidate(
                    id: activity.id, name: activity.name, courseName: activity.courseName, due: activity.due,
                    isSubmitted: workspace.state(of: activity, now: now) == .submitted,
                    colorHex: course.map { WidgetCourseColor.hex(forCourseNumber: $0.number) } ?? WidgetCourseColor.hexes[0])
            }
            var focusInfo: WidgetSnapshot.Focus?
            if let running = focus.timer.running, running.phase == .focus {
                focusInfo = WidgetSnapshot.Focus(activityName: focus.activityName ?? "Enfoque", endsAt: running.phaseEnd)
            }
            return WidgetSnapshotBuilder.build(now: now, candidates: candidates, cardsDue: review.todayCount(today: ReviewDay(date: now)),
                                               focus: focusInfo)
        }
    }
}
