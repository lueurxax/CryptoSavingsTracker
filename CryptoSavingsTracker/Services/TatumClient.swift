//
//  TatumClient.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 06/08/2025.
//

import Foundation
import os

// MARK: - Base HTTP Client
final class TatumClient {
    static let shared = TatumClient()
    
    private let apiKey: String
    let baseURL = "https://api.tatum.io/v3"
    let v4BaseURL = "https://api.tatum.io/v4"
    let solanaRPCURL = "https://api.mainnet-beta.solana.com"
    private static let log = Logger(subsystem: "xax.CryptoSavingsTracker", category: "TatumClient")
    
    init() {
        apiKey = Self.loadAPIKey()
    }
    
    private static func loadAPIKey() -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["TatumAPIKey"] as? String else {
            log.error("Warning: Could not load Tatum API key from Config.plist")
            return "YOUR_TATUM_API_KEY"
        }
        return key
    }
    
    // MARK: - HTTP Request Methods
    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        Self.log.debug("Performing HTTP request - URL: \(request.url?.absoluteString ?? "nil"), Method: \(request.httpMethod ?? "GET")")
        
        guard !apiKey.isEmpty && apiKey != "YOUR_TATUM_API_KEY" else {
            Self.log.error("Missing or invalid API key")
            throw TatumError.missingAPIKey
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        Self.log.debug("HTTP response received - Status: \(statusCode), Data size: \(data.count) bytes")
        
        try validateResponse(response)
        return (data, response)
    }
    
    func createV3Request(path: String, queryItems: [URLQueryItem] = []) -> URLRequest? {
        let urlString = "\(baseURL)\(path)"
        var components = URLComponents(string: urlString)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            Self.log.error("Invalid V3 URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "accept")
        return request
    }
    
    func createV4Request(path: String, queryItems: [URLQueryItem] = []) -> URLRequest? {
        let urlString = "\(v4BaseURL)\(path)"
        var components = URLComponents(string: urlString)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            Self.log.error("Invalid V4 URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "accept")
        return request
    }
    
    func createLegacyRequest(path: String, queryItems: [URLQueryItem] = []) -> URLRequest? {
        let urlString = "\(baseURL)\(path)"
        var components = URLComponents(string: urlString)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            Self.log.error("Invalid legacy URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    func createSolanaRPCRequest(method: String, params: [SolanaRPCParam]) -> URLRequest? {
        guard let url = URL(string: self.solanaRPCURL) else {
            Self.log.error("Invalid Solana RPC URL: \(self.solanaRPCURL)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let rpcRequest = SolanaRPCRequest(method: method, params: params)
        
        do {
            let jsonData = try JSONEncoder().encode(rpcRequest)
            request.httpBody = jsonData
        } catch {
            Self.log.error("Failed to encode Solana RPC request: \(error)")
            return nil
        }
        
        return request
    }
    
    // MARK: - Response Validation
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.log.error("Response validation failed: Not an HTTP response")
            throw TatumError.invalidResponse
        }
        
        Self.log.debug("Validating HTTP response - Status code: \(httpResponse.statusCode)")
        
        switch httpResponse.statusCode {
        case 200...299:
            Self.log.debug("HTTP response validation passed")
            return
        case 401:
            Self.log.error("HTTP 401 Unauthorized - API key may be invalid")
            throw TatumError.unauthorized
        case 403:
            Self.log.error("HTTP 403 Forbidden - Rate limit exceeded or access denied")
            throw TatumError.rateLimitExceeded
        case 404:
            Self.log.error("HTTP 404 Not Found - Address or endpoint not found")
            throw TatumError.notFound
        default:
            Self.log.error("HTTP \(httpResponse.statusCode) - Unexpected status code")
            throw TatumError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Error Handling
enum TatumError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimitExceeded
    case notFound
    case unsupportedChain(String)
    case httpError(Int)
    case decodingError(Error)
}

extension TatumError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Tatum API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Tatum API"
        case .unauthorized:
            return "Unauthorized - check your API key"
        case .rateLimitExceeded:
            return "API rate limit exceeded - please try again later"
        case .notFound:
            return "Address or resource not found"
        case .unsupportedChain(let chainId):
            return "Unsupported chain: \(chainId)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}