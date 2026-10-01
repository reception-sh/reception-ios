import SwiftUI

extension ChatModel {
    func schedulePending(_ id: String) {
        clearPending(id)
        pendingTimers[id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled, let self, self.current,
                  let index = self.messages.firstIndex(where: { $0.id == id }),
                  self.messages[index].status == .sending else { return }
            withAnimation(Theme.deliveryStatusAnimation) { self.messages[index].showsPending = true }
        }
    }

    func clearPending(_ id: String) {
        pendingTimers.removeValue(forKey: id)?.cancel()
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].showsPending = false
        }
    }
}
