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

public enum BookContentKind: String, Codable, Equatable, Sendable {
    case text
    case comic
    case uncertain
}

public enum ConversionProfile: String, Codable, Equatable, Sendable {
    case textReflow
    case comicFixedLayout
}

public enum ImportSource: String, Codable, Equatable, Sendable {
    case browserDownload
    case filePicker
    case dragAndDrop
}

public struct ClassificationResult: Codable, Equatable, Sendable {
    public let kind: BookContentKind
    public let confidence: Double
    public let evidence: String

    public init(kind: BookContentKind, confidence: Double, evidence: String) {
        self.kind = kind
        self.confidence = min(max(confidence, 0), 1)
        self.evidence = evidence
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
    public var importSource: ImportSource?
    public var detectedKind: BookContentKind?
    public var conversionProfile: ConversionProfile
    public var readingDirection: EpubReadingDirection

    public init(
        id: UUID = UUID(),
        inputURL: URL,
        outputURL: URL? = nil,
        status: ConversionStatus = .queued,
        progress: Double = 0,
        statusMessage: String = "Waiting",
        log: String = "",
        reportURL: URL? = nil,
        completedAt: Date? = nil,
        importSource: ImportSource? = nil,
        detectedKind: BookContentKind? = nil,
        conversionProfile: ConversionProfile = .comicFixedLayout,
        readingDirection: EpubReadingDirection = .rightToLeft
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
        self.importSource = importSource
        self.detectedKind = detectedKind
        self.conversionProfile = conversionProfile
        self.readingDirection = readingDirection
    }
}

extension ConversionTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, inputURL, outputURL, status, progress, statusMessage, log, reportURL, completedAt
        case importSource, detectedKind, conversionProfile, readingDirection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        inputURL = try container.decode(URL.self, forKey: .inputURL)
        outputURL = try container.decodeIfPresent(URL.self, forKey: .outputURL)
        status = try container.decode(ConversionStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        statusMessage = try container.decode(String.self, forKey: .statusMessage)
        log = try container.decode(String.self, forKey: .log)
        reportURL = try container.decodeIfPresent(URL.self, forKey: .reportURL)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        importSource = try container.decodeIfPresent(ImportSource.self, forKey: .importSource)
        detectedKind = try container.decodeIfPresent(BookContentKind.self, forKey: .detectedKind)
        conversionProfile = try container.decodeIfPresent(ConversionProfile.self, forKey: .conversionProfile) ?? .comicFixedLayout
        readingDirection = try container.decodeIfPresent(EpubReadingDirection.self, forKey: .readingDirection) ?? .rightToLeft
    }
}
