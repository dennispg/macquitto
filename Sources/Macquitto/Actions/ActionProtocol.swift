import Foundation

protocol Action {
    var id: String { get }
    var commandTopic: String { get }

    func execute(payload: String) async throws
}
