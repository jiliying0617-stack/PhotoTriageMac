import Foundation

/// FIFO for overlapping files, while unrelated files remain independent.
@MainActor
final class FileMutationGate {
    private var held: Set<UUID> = []
    private var waiters: [(ids: Set<UUID>, continuation: CheckedContinuation<Void, Never>)] = []

    func acquire(_ ids: Set<UUID>) async {
        await withCheckedContinuation { continuation in
            waiters.append((ids, continuation))
            drain()
        }
    }

    func release(_ ids: Set<UUID>) {
        held.subtract(ids)
        drain()
    }

    private func drain() {
        var blocked: Set<UUID> = []
        var remaining: [(ids: Set<UUID>, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if held.isDisjoint(with: waiter.ids), blocked.isDisjoint(with: waiter.ids) {
                held.formUnion(waiter.ids)
                waiter.continuation.resume()
            } else {
                blocked.formUnion(waiter.ids)
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}
