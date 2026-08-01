import Foundation

enum APIError: LocalizedError {
    case httpStatus(code: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "HTTP \(code): \(message)"
            }
            return "HTTP \(code)"
        }
    }
}

struct DeadlineAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateFormatter: DateFormatter
    private let legacyDateFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private let isoFractionFormatter: ISO8601DateFormatter
    private let getToken: () -> String?

    init(baseURL: URL, session: URLSession? = nil, tokenProvider: @escaping () -> String? = { AuthService.shared.token }) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 180
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
        self.getToken = tokenProvider

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        self.dateFormatter = formatter

        let legacy = DateFormatter()
        legacy.locale = Locale(identifier: "en_US_POSIX")
        legacy.dateFormat = "yyyy-MM-dd"
        legacy.timeZone = .current
        self.legacyDateFormatter = legacy

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        self.isoFormatter = iso

        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFractionFormatter = isoFraction
    }
    
    private func authRequest(_ request: inout URLRequest) {
        if let token = getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func fetchDeadlines(filter: DeadlineFilter) async throws -> [DeadlineDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("deadlines"), resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = []
        if let status = filter.status { query.append(URLQueryItem(name: "status", value: status)) }
        if let subject = filter.subject { query.append(URLQueryItem(name: "subject", value: subject)) }
        components?.queryItems = query.isEmpty ? nil : query

        let url = components?.url ?? baseURL.appendingPathComponent("deadlines")
        var request = URLRequest(url: url)
        authRequest(&request)
        let (data, _) = try await validatedData(for: request)

        let payloads = try decoder.decode([ServerDeadline].self, from: data)
        return payloads.map(makeDTO(from:))
    }

    func createDeadline(_ dto: DeadlineDTO) async throws -> DeadlineDTO {
        try await send(dto, method: "POST", endpoint: baseURL.appendingPathComponent("deadlines"))
    }

    func updateDeadline(_ dto: DeadlineDTO) async throws -> DeadlineDTO {
        let identifier = dto.remoteID ?? dto.id
        let endpoint = baseURL.appendingPathComponent("deadlines/\(identifier)")
        return try await send(dto, method: "PUT", endpoint: endpoint)
    }

    func deleteDeadline(id: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("deadlines/\(id)"))
        request.httpMethod = "DELETE"
        authRequest(&request)
        _ = try await validatedData(for: request)
    }

    // MARK: - Helpers

    private func send(_ dto: DeadlineDTO, method: String, endpoint: URL) async throws -> DeadlineDTO {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        authRequest(&request)

        let payload = makePayload(from: dto)
        request.httpBody = try encoder.encode(payload)

        let (data, _) = try await validatedData(for: request)

        let responsePayload = try decoder.decode(ServerDeadline.self, from: data)
        return makeDTO(from: responsePayload)
    }

    private func validatedData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = parseServerMessage(from: data)
            throw APIError.httpStatus(code: http.statusCode, message: message)
        }

        return (data, http)
    }

    private func dataWithRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        let maxAttempts = 4
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                attempt += 1

                guard attempt < maxAttempts, shouldRetry(error) else {
                    throw error
                }

                let delayNanos = UInt64(1_000_000_000 * attempt)
                try? await Task.sleep(nanoseconds: delayNanos)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    private func parseServerMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String {
                return error
            }
            if let message = json["message"] as? String {
                return message
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180).description
        }

        return nil
    }

    private func makePayload(from dto: DeadlineDTO) -> ServerDeadline {
        ServerDeadline(
            id: dto.remoteID ?? "",
            title: dto.title,
            subject: dto.subject,
            dueDate: dateFormatter.string(from: dto.dueDate),
            status: dto.status,
            tags: dto.tags,
            repeatType: dto.repeatType,
            notes: dto.notes,
            reminderTime: dto.reminderTime,
            deletedAt: encodeDeletedAt(dto.deletedAt)
        )
    }

    private func makeDTO(from payload: ServerDeadline) -> DeadlineDTO {
        let dueDate = dateFormatter.date(from: payload.dueDate)
            ?? legacyDateFormatter.date(from: payload.dueDate)
            ?? Date()
        let deletedAt = parseDeletedAt(payload.deletedAt)
        return DeadlineDTO(
            id: payload.id,
            remoteID: payload.id,
            title: payload.title,
            subject: payload.subject,
            dueDate: dueDate,
            status: payload.status,
            priority: "Авто",
            tags: payload.tags ?? [],
            repeatType: payload.repeatType ?? "none",
            notes: payload.notes ?? "",
            reminderTime: payload.reminderTime ?? "1day",
            updatedAt: Date(),
            deletedAt: deletedAt,
            isDirty: false,
            isDeleted: false
        )
    }

    private func encodeDeletedAt(_ date: Date?) -> String? {
        guard let date else { return nil }
        return isoFormatter.string(from: date)
    }

    private func parseDeletedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = dateFormatter.date(from: raw) { return date }
        if let date = legacyDateFormatter.date(from: raw) { return date }
        if let date = isoFractionFormatter.date(from: raw) { return date }
        return isoFormatter.date(from: raw)
    }

    private struct ServerDeadline: Codable {
        let id: String
        let title: String
        let subject: String
        let dueDate: String
        let status: String
        let tags: [String]?
        let repeatType: String?
        let notes: String?
        let reminderTime: String?
        let deletedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case id, title, subject, dueDate, status, tags, repeatType, notes, reminderTime, deletedAt
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // ID может приходить как Int или String
            if let intId = try? container.decode(Int.self, forKey: .id) {
                id = String(intId)
            } else {
                id = try container.decode(String.self, forKey: .id)
            }
            
            title = try container.decode(String.self, forKey: .title)
            subject = try container.decode(String.self, forKey: .subject)
            dueDate = try container.decode(String.self, forKey: .dueDate)
            status = try container.decode(String.self, forKey: .status)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            repeatType = try container.decodeIfPresent(String.self, forKey: .repeatType)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            reminderTime = try container.decodeIfPresent(String.self, forKey: .reminderTime)
            deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        }
        
        init(id: String, title: String, subject: String, dueDate: String, status: String, tags: [String]?, repeatType: String?, notes: String?, reminderTime: String?, deletedAt: String?) {
            self.id = id
            self.title = title
            self.subject = subject
            self.dueDate = dueDate
            self.status = status
            self.tags = tags
            self.repeatType = repeatType
            self.notes = notes
            self.reminderTime = reminderTime
            self.deletedAt = deletedAt
        }
    }

}
