import Foundation

public class ExperimentImpl {
    public let name: String
    public let group: String
    public let subjectId: String?
    public let isLoggable: () -> Bool
    public let coordinator: String

    public init(
        name: String,
        group: String,
        subjectId: String? = nil,
        isLoggable: @escaping () -> Bool = { true },
        coordinator: String = Event.EventExperiment.coordinatorCustom
    ) {
        self.name = name
        self.group = group
        self.subjectId = subjectId
        self.isLoggable = isLoggable
        self.coordinator = coordinator
    }
}
