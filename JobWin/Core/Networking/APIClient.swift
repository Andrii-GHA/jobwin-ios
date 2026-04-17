import Foundation

struct MultipartFormFile {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

struct APIClient {
    let baseURL: String
    let accessToken: String

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET")
        return try await send(request)
    }

    func post<Response: Decodable>(_ path: String) async throws -> Response {
        try await post(path, body: EmptyBody())
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    func postMultipart<Response: Decodable>(
        _ path: String,
        fields: [String: String] = [:],
        file: MultipartFormFile
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = makeMultipartBody(fields: fields, file: file, boundary: boundary)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    func delete<Response: Decodable>(_ path: String) async throws -> Response {
        let request = try makeRequest(path: path, method: "DELETE")
        return try await send(request)
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = try makeRequest(path: path, method: "PATCH")
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let normalizedPath = normalizePath(path)

        guard let url = URL(string: "\(baseURL)\(normalizedPath)") else {
            throw APIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func normalizePath(_ path: String) -> String {
        let legacyPrefix = "/api/mobile/"
        let versionedPrefix = "/api/mobile/v1/"

        guard path.hasPrefix(legacyPrefix), !path.hasPrefix(versionedPrefix) else {
            return path
        }

        return versionedPrefix + path.dropFirst(legacyPrefix.count)
    }

    private func makeMultipartBody(
        fields: [String: String],
        file: MultipartFormFile,
        boundary: String
    ) -> Data {
        let lineBreak = "\r\n"
        var body = Data()

        for (key, value) in fields where !value.isEmpty {
            body.append(Data("--\(boundary)\(lineBreak)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".utf8))
            body.append(Data("\(value)\(lineBreak)".utf8))
        }

        body.append(Data("--\(boundary)\(lineBreak)".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\(lineBreak)"
                    .utf8
            )
        )
        body.append(Data("Content-Type: \(file.mimeType)\(lineBreak)\(lineBreak)".utf8))
        body.append(file.data)
        body.append(Data(lineBreak.utf8))
        body.append(Data("--\(boundary)--\(lineBreak)".utf8))

        return body
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed."
            throw APIClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

enum APIClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid API base URL."
        case .invalidResponse:
            return "Invalid server response."
        case let .requestFailed(statusCode, message):
            return "Request failed (\(statusCode)): \(message)"
        }
    }
}
