import SwiftData
import SwiftUI

struct GoalCompletionFlowModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var request: Goal?
    let onFinished: (Goal) -> Void

    @State private var coordinator = GoalCompletionFlowCoordinator()
    @State private var errorMessage = ""
    @State private var isErrorAlertPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id, initial: true) { _, _ in
                guard let goal = request else {
                    if coordinator.goal != nil {
                        coordinator.cancel()
                    }
                    return
                }
                Task { await start(goal) }
            }
            .sheet(isPresented: decisionSheetBinding) {
                GoalCompletionSettlementSheet(
                    coordinator: coordinator,
                    onApply: {
                        Task { await apply() }
                    },
                    onCancel: cancel
                )
            }
            .alert("Couldn’t Finish Goal", isPresented: $isErrorAlertPresented) {
                Button("Retry") {
                    Task { await retry() }
                }
                Button("Cancel", role: .cancel, action: cancel)
            } message: {
                Text(errorMessage)
            }
    }

    private var decisionSheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isDecisionSheetPresented },
            set: { isPresented in
                if isPresented == false, coordinator.phase != .applying {
                    cancel()
                }
            }
        )
    }

    private func start(_ goal: Goal) async {
        let service = GoalLifecycleService(modelContext: modelContext)
        await coordinator.start(
            goal: goal,
            prepare: { goal in
                try service.prepareFinishGoal(goal)
            },
            apply: { goal, plan, decisions in
                try await service.finishGoal(goal, plan: plan, decisions: decisions)
            }
        )
        finishIfSuccessful(goal)
        presentErrorIfNeeded()
    }

    private func apply() async {
        guard let goal = coordinator.goal else { return }
        let service = GoalLifecycleService(modelContext: modelContext)
        await coordinator.apply { goal, plan, decisions in
            try await service.finishGoal(goal, plan: plan, decisions: decisions)
        }
        finishIfSuccessful(goal)
        presentErrorIfNeeded()
    }

    private func retry() async {
        isErrorAlertPresented = false
        guard let goal = coordinator.goal ?? request else { return }
        if coordinator.plan != nil, coordinator.canApply {
            await apply()
        } else {
            await start(goal)
        }
    }

    private func finishIfSuccessful(_ goal: Goal) {
        guard coordinator.phase == .idle, request?.id == goal.id else { return }
        request = nil
        onFinished(goal)
    }

    private func presentErrorIfNeeded() {
        guard case let .failed(message) = coordinator.phase else { return }
        errorMessage = message
        isErrorAlertPresented = true
    }

    private func cancel() {
        isErrorAlertPresented = false
        coordinator.cancel()
        request = nil
    }
}

extension View {
    func goalCompletionFlow(
        request: Binding<Goal?>,
        onFinished: @escaping (Goal) -> Void
    ) -> some View {
        modifier(GoalCompletionFlowModifier(request: request, onFinished: onFinished))
    }
}
