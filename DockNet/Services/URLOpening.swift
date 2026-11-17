import AppKit
import Foundation

/// Protocol abstracting system URL opening to allow deterministic testing without launching web browsers.
public protocol URLOpening: Sendable {
    @MainActor @discardableResult
    func open(_ url: URL) -> Bool
}

/// Production URL opener utilizing NSWorkspace.
public struct WorkspaceURLOpener: URLOpening {
    public init() {}

    @MainActor @discardableResult
    public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

/// Mock URL opener for unit and UI automation testing. All stored URLs are protected by `lock`.
public final class MockURLOpener: @unchecked Sendable, URLOpening {
    private let lock = NSLock()
    private var _openedURLs: [URL] = []

    public init() {}

    @discardableResult
    public func open(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _openedURLs.append(url)
        return true
    }

    public var openedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _openedURLs
    }

    public var lastOpenedURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _openedURLs.last
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _openedURLs.removeAll()
    }
}
