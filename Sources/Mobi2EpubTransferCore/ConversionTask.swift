import Foundation

public enum ConversionStatus: String, Codable, Equatable, Sendable {
    case queued
    case checkingTools
    case converting
    case validating
    case succeeded
    case succeededWithWarnings
    case failed

    public var displayName: String {
        switch self {
        case .queued: "Queued"
        case .checkingTools: "Checking tools"
        case .converting: "Converting"
        case .validating: "Validating"
        case .succeeded: "Succeeded"
        case .succeededWithWarnings: "Succeeded with warnings"
        case .failed: "Failed"
        }
    }
}

public struct ConversionTask: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let inputURL: URL
    public var outputURL: URL?
    public var status: ConversionStatus
    public var progress: Double
    public var statusMessage: String
    public var log: String
    public var reportURL: URL?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        inputURL: URL,
        outputURL: URL? = nil,
        status: ConversionStatus = .queued,
        progress: Double = 0,
        statusMessage: String = "Waiting",
        log: String = "",
        reportURL: URL? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.status = status
        self.progress = progress
        self.statusMessage = statusMessage
        self.log = log
        self.reportURL = reportURL
        self.completedAt = completedAt
    }
}

extension ConversionTask: Codable {}
