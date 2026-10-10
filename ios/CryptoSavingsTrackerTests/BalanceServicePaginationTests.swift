import Foundation
import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class BalanceServicePaginationTests: XCTestCase {
    func testTokenOnSecondPageIsReturnedAndCached() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(symbols: (0..<50).map { "TOKEN\($0)" }, nextPage: fixture.pageURL(offset: 50))
        fixture.pages[50] = .portfolio(symbols: ["USDT"], amount: "42000000", nextPage: "")
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        let balance = try await service.fetchBalance(chainId: "ETH", address: fixture.address, symbol: "USDT")

        XCTAssertEqual(balance, 42)
        XCTAssertEqual(BalanceCacheManager.shared.getCachedBalance(for: fixture.cacheKey), 42)
        XCTAssertEqual(fixture.requestOffsets, [0, 50])
        XCTAssertTrue(fixture.requests.allSatisfy {
            $0.url?.host == "api.tatum.io" && $0.url?.path == "/v4/data/wallet/portfolio"
        })
        let secondQuery = URLComponents(url: try XCTUnwrap(fixture.requests.last?.url), resolvingAgainstBaseURL: false)
        XCTAssertEqual(secondQuery?.queryItems?.first { $0.name == "addresses" }?.value, fixture.address)
        XCTAssertEqual(secondQuery?.queryItems?.first { $0.name == "tokenTypes" }?.value, "fungible")
    }

    func testNumericNextPageOffsetIsFollowed() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(symbols: ["DAI"], nextPage: "50")
        fixture.pages[50] = .portfolio(symbols: ["USDT"], amount: "42000000", nextPage: nil)
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        let balance = try await service.fetchBalance(chainId: "ETH", address: fixture.address, symbol: "USDT")

        XCTAssertEqual(balance, 42)
        XCTAssertEqual(fixture.requestOffsets, [0, 50])
    }

    func testMissingTokenReturnsZeroOnlyAfterEveryPage() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(symbols: ["DAI"], nextPage: fixture.pageURL(offset: 50))
        fixture.pages[50] = .portfolio(symbols: ["USDC"], nextPage: fixture.pageURL(offset: 100))
        fixture.pages[100] = .portfolio(symbols: [], nextPage: nil)
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        let balance = try await service.fetchBalance(chainId: "ETH", address: fixture.address, symbol: "USDT")

        XCTAssertEqual(balance, 0)
        XCTAssertEqual(fixture.requestOffsets, [0, 50, 100])
        XCTAssertEqual(BalanceCacheManager.shared.getCachedBalance(for: fixture.cacheKey), 0)
    }

    func testLaterPageFailureDoesNotCacheAFalseZero() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(symbols: ["DAI"], nextPage: fixture.pageURL(offset: 50))
        fixture.pages[50] = .failure
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        do {
            _ = try await service.fetchBalance(chainId: "ETH", address: fixture.address, symbol: "USDT")
            XCTFail("An incomplete portfolio must fail instead of becoming a zero balance")
        } catch TatumError.httpError(400) {
            // The later page failed, so no complete balance can be cached.
        }
        XCTAssertNil(BalanceCacheManager.shared.getFallbackBalance(for: fixture.cacheKey))
    }

    func testLaterPageFailurePreservesTheFallbackBalance() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(symbols: ["DAI"], nextPage: fixture.pageURL(offset: 50))
        fixture.pages[50] = .failure
        BalanceCacheManager.shared.cacheBalance(7, for: fixture.cacheKey)
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        do {
            _ = try await service.fetchBalance(
                chainId: "ETH", address: fixture.address, symbol: "USDT", forceRefresh: true
            )
            XCTFail("An incomplete refresh must report failure instead of presenting cached funds as current")
        } catch TatumError.httpError(400) {
            // Retain the last balance for degraded presentation without treating it as a successful refresh.
        }
        XCTAssertEqual(BalanceCacheManager.shared.getFallbackBalance(for: fixture.cacheKey), 7)
    }

    func testRepeatedPageOffsetFailsWithoutCaching() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(symbols: ["DAI"], nextPage: fixture.pageURL(offset: 50))
        fixture.pages[50] = .portfolio(symbols: ["USDC"], nextPage: fixture.pageURL(offset: 50))
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        await assertInvalidPagination(service, fixture: fixture)

        XCTAssertEqual(fixture.requestOffsets, [0, 50])
    }

    func testUntrustedPageURLIsRejectedBeforeSendingCredentials() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(
            symbols: ["DAI"], nextPage: "https://untrusted.example/v4/data/wallet/portfolio?offset=50"
        )
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        await assertInvalidPagination(service, fixture: fixture)

        XCTAssertEqual(fixture.requestOffsets, [0])
        XCTAssertTrue(fixture.requests.allSatisfy { $0.url?.host == "api.tatum.io" })
    }

    func testMalformedPageOffsetsFailWithoutCaching() async throws {
        for nextPage in ["-1", "not-an-offset", "https://api.tatum.io/v4/data/wallet/portfolio?offset=NaN"] {
            let fixture = PortfolioFixture()
            fixture.pages[0] = .portfolio(symbols: ["DAI"], nextPage: nextPage)
            let (service, session) = makeService(fixture)
            defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

            await assertInvalidPagination(service, fixture: fixture)

            XCTAssertEqual(fixture.requestOffsets, [0])
        }
    }

    func testNativeBalanceWithoutAnotherPageKeepsItsDenomination() async throws {
        let fixture = PortfolioFixture()
        fixture.pages[0] = .portfolio(
            symbols: ["ETH"], amount: "1500000000000000000", decimals: 18, type: "native", nextPage: ""
        )
        let (service, session) = makeService(fixture)
        defer { session.invalidateAndCancel(); PortfolioURLProtocol.remove(fixture) }

        let balance = try await service.fetchBalance(chainId: "ETH", address: fixture.address, symbol: "ETH")

        XCTAssertEqual(balance, 1.5)
        XCTAssertEqual(fixture.requestOffsets, [0])
    }

    private func assertInvalidPagination(_ service: BalanceService, fixture: PortfolioFixture) async {
        do {
            _ = try await service.fetchBalance(chainId: "ETH", address: fixture.address, symbol: "USDT")
            XCTFail("Invalid pagination must fail instead of producing a partial zero balance")
        } catch TatumError.invalidResponse {
            // Invalid continuation must not be treated as a complete portfolio.
        } catch {
            XCTFail("Unexpected pagination error: \(error)")
        }
        XCTAssertNil(BalanceCacheManager.shared.getFallbackBalance(for: fixture.cacheKey))
    }

    private func makeService(_ fixture: PortfolioFixture) -> (BalanceService, URLSession) {
        PortfolioURLProtocol.install(fixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = TatumClient(apiKey: "fixture-only-api-key", session: session)
        return (BalanceService(client: client, chainService: ChainService()), session)
    }
}

private final class PortfolioFixture: @unchecked Sendable {
    enum Page {
        case portfolio(symbols: [String], amount: String = "1000000", decimals: Int = 6,
                       type: String = "fungible", nextPage: String?)
        case failure

        func response(address: String) throws -> (Int, Data) {
            switch self {
            case let .portfolio(symbols, amount, decimals, type, nextPage):
                let items = symbols.map {
                    TatumV4BalanceItem(chain: "ethereum-mainnet", address: address, balance: "1",
                                       denominatedBalance: amount, decimals: decimals, type: type,
                                       tokenAddress: $0 == "USDT" ? "0xdAC17F958D2ee523a2206206994597C13D831ec7" : "0x\($0)",
                                       tokenName: $0, tokenSymbol: $0)
                }
                let response = TatumV4PortfolioResponse(result: items, prevPage: "", nextPage: nextPage)
                return (200, try JSONEncoder().encode(response))
            case .failure:
                return (400, Data("invalid page".utf8))
            }
        }
    }

    let address = "0x-pagination-\(UUID().uuidString)"
    var pages: [Int: Page] = [:]
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    var cacheKey: String {
        BalanceCacheManager.balanceCacheKey(chainId: "ETH", address: address, symbol: "USDT")
    }
    var requests: [URLRequest] { lock.withLock { recordedRequests } }
    var requestOffsets: [Int] {
        requests.map { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            return Int(components?.queryItems?.first { $0.name == "offset" }?.value ?? "0") ?? -1
        }
    }

    func pageURL(offset: Int) -> String {
        "https://api.tatum.io/v4/data/wallet/portfolio?chain=ethereum-mainnet"
            + "&addresses=\(address)&tokenTypes=fungible&offset=\(offset)"
    }

    func response(for request: URLRequest) throws -> (Int, Data) {
        lock.withLock { recordedRequests.append(request) }
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let offset = Int(components?.queryItems?.first { $0.name == "offset" }?.value ?? "0") ?? -1
        return try (pages[offset] ?? .failure).response(address: address)
    }
}

private final class PortfolioURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: PortfolioFixture] = [:]

    static func install(_ fixture: PortfolioFixture) {
        lock.withLock { fixtures[fixture.address] = fixture }
    }

    static func remove(_ fixture: PortfolioFixture) {
        _ = lock.withLock { fixtures.removeValue(forKey: fixture.address) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let address = components?.queryItems?.first { $0.name == "addresses" }?.value ?? ""
            let fixture = try XCTUnwrap(Self.lock.withLock { Self.fixtures[address] })
            let (statusCode, data) = try fixture.response(for: request)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode,
                                                       httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
