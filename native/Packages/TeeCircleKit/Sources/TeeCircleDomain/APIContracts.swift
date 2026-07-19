import Foundation

public struct APIEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public static var supportedSchemaVersion: Int { 1 }

    public let schemaVersion: Int
    public let requestId: String
    public let data: Payload

    public init(schemaVersion: Int = Self.supportedSchemaVersion, requestId: String, data: Payload) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.data = data
    }
}

extension APIEnvelope: Equatable where Payload: Equatable {}
extension APIEnvelope: Hashable where Payload: Hashable {}

public struct APIErrorEnvelope: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: Int
    public let requestId: String
    public let error: APIErrorPayload

    public init(schemaVersion: Int = 1, requestId: String, error: APIErrorPayload) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.error = error
    }
}

public struct APIErrorPayload: Codable, Equatable, Hashable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let currentRevision: Int?
    public let details: [String: JSONValue]?

    public init(
        code: String,
        message: String,
        retryable: Bool,
        currentRevision: Int? = nil,
        details: [String: JSONValue]? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.currentRevision = currentRevision
        self.details = details
    }
}

/// Lossless JSON used for stable, command-specific error details such as the
/// current hole value returned with an optimistic-concurrency conflict.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON error detail."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var intValue: Int? {
        guard case let .number(value) = self else { return nil }
        return Int(exactly: value)
    }
}

public struct EmptyPayload: Codable, Equatable, Hashable, Sendable {
    public init() {}
}

public struct ScoreHoleCommandV1: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: Int
    public let roundId: String
    public let tripPlayerId: String
    public let hole: Int
    /// Played strokes before separately recorded penalty strokes.
    public let strokes: Int
    public let expectedRevision: Int
    public let idempotencyKey: String

    public init(
        schemaVersion: Int = 1,
        roundId: String,
        tripPlayerId: String,
        hole: Int,
        strokes: Int,
        expectedRevision: Int,
        idempotencyKey: String
    ) {
        self.schemaVersion = schemaVersion
        self.roundId = roundId
        self.tripPlayerId = tripPlayerId
        self.hole = hole
        self.strokes = strokes
        self.expectedRevision = expectedRevision
        self.idempotencyKey = idempotencyKey
    }
}

public struct ScoreHoleResultV1: Codable, Equatable, Hashable, Sendable {
    public let revision: Int
    public let snapshot: LeaderboardSnapshotV1

    public init(revision: Int, snapshot: LeaderboardSnapshotV1) {
        self.revision = revision
        self.snapshot = snapshot
    }
}
