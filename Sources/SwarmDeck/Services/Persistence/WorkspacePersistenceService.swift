import Foundation

/// Represents the persisted declarative topology of the SwarmDeck workspace.
///
/// Contains active agent sessions, the currently focused session,
/// and metadata for crash-resilient restoration. Conforms to Swift 6 `Sendable` and `Codable`.
public struct WorkspaceTopology: Sendable, Equatable, Codable {
    /// Schema version for forward/backward compatibility migrations.
    public var version: Int
    
    /// List of persisted sessions.
    public var sessions: [Session]
    
    /// The unique identifier of the currently selected/active session, if any.
    public var selectedSessionId: UUID?
    
    /// Timestamp of when this topology was last serialized to disk.
    public var lastSavedAt: Date
    
    /// Indicates whether the application terminated via an orderly shutdown sequence.
    /// If `false`, the next application launch detects an abnormal crash or termination.
    public var cleanShutdown: Bool
    
    public init(
        version: Int = 1,
        sessions: [Session] = [],
        selectedSessionId: UUID? = nil,
        lastSavedAt: Date = Date(),
        cleanShutdown: Bool = false
    ) {
        self.version = version
        self.sessions = sessions
        self.selectedSessionId = selectedSessionId
        self.lastSavedAt = lastSavedAt
        self.cleanShutdown = cleanShutdown
    }
}

/// Policy determining which restored sessions should have their underlying
/// processes automatically restarted when restoring workspace topology on launch.
public enum AutoRestartPolicy: String, Sendable, Equatable, Codable, CaseIterable {
    /// Sessions are restored in their persisted state without launching any processes.
    case disabled
    
    /// Only safe presets (e.g. standard shell) are automatically restarted.
    /// Potentially destructive or paid AI agent sessions (e.g. Claude Code, Aider, Antigravity)
    /// remain in idle/stopped state until explicitly resumed by the user.
    case safePresetsOnly
    
    /// All sessions are automatically re-spawned upon launch.
    case allPresets
}

extension AgentPreset {
    /// Indicates whether this agent preset is safe for automatic background respawning
    /// without explicit user initiation upon app launch.
    public var isSafeForAutoRestart: Bool {
        id == AgentPreset.standardShell.id || id == "shell"
    }
}

/// Errors thrown by the workspace persistence service.
public enum WorkspacePersistenceError: Error, Sendable, Equatable, CustomStringConvertible {
    case directoryCreationFailed(String)
    case serializationFailed(String)
    case deserializationFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case corruptedData(String)
    
    public var description: String {
        switch self {
        case .directoryCreationFailed(let msg):
            return "Failed to create persistence directory: \(msg)"
        case .serializationFailed(let msg):
            return "Failed to serialize workspace topology to JSON: \(msg)"
        case .deserializationFailed(let msg):
            return "Failed to deserialize workspace topology: \(msg)"
        case .writeFailed(let msg):
            return "Failed to write workspace topology file: \(msg)"
        case .readFailed(let msg):
            return "Failed to read workspace topology file: \(msg)"
        case .corruptedData(let msg):
            return "Corrupted workspace data: \(msg)"
        }
    }
}

/// Crash-resilient persistence service managing declarative workspace topology.
///
/// Features:
/// - 100% Swift 6 strict concurrency (`actor` isolation).
/// - Atomic file writes using temporary file swap (`workspace.json.tmp` -> `rename()` -> `workspace.json`).
/// - Debounced file writes (default 500ms) to prevent disk I/O churn during rapid session edits.
/// - Graceful crash recovery with automated backup of corrupted files (`workspace.json.corrupted-<timestamp>`).
/// - Clean shutdown vs crash detection.
public actor WorkspacePersistenceService {
    public static let shared = WorkspacePersistenceService()
    
    public static let defaultDirectoryURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/swarmdeck", isDirectory: true)
    }()
    
    public static let defaultFileURL: URL = {
        defaultDirectoryURL.appendingPathComponent("workspace.json", isDirectory: false)
    }()
    
    public static let defaultTempFileURL: URL = {
        defaultDirectoryURL.appendingPathComponent("workspace.json.tmp", isDirectory: false)
    }()
    
    public let fileURL: URL
    public let tempFileURL: URL
    public let debounceInterval: Duration
    
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingTopology: WorkspaceTopology?
    
    public init(
        fileURL: URL = WorkspacePersistenceService.defaultFileURL,
        tempFileURL: URL? = nil,
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.fileURL = fileURL
        self.tempFileURL = tempFileURL ?? fileURL.deletingPathExtension().appendingPathExtension("json.tmp")
        self.debounceInterval = debounceInterval
    }
    
    deinit {
        pendingSaveTask?.cancel()
    }
    
    // MARK: - Debounced Persistence
    
    /// Schedules a debounced save operation.
    ///
    /// Subsequent calls within the `debounceInterval` window reset the timer, coalescing
    /// rapid workspace mutations into a single atomic disk write.
    public func scheduleSave(topology: WorkspaceTopology) {
        pendingTopology = topology
        pendingSaveTask?.cancel()
        
        pendingSaveTask = Task { [weak self, debounceInterval] in
            do {
                try await Task.sleep(for: debounceInterval)
            } catch {
                return // Task was cancelled
            }
            
            await self?.flushPendingSave()
        }
    }
    
    /// Flushes any pending debounced save immediately to disk.
    public func flush() throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        if let topology = pendingTopology {
            pendingTopology = nil
            try saveImmediately(topology)
        }
    }
    
    private func flushPendingSave() {
        guard let topology = pendingTopology else { return }
        pendingTopology = nil
        pendingSaveTask = nil
        do {
            try saveImmediately(topology)
        } catch {
            print("WorkspacePersistenceService debounce flush error: \(error)")
        }
    }
    
    // MARK: - Atomic Synchronous / Immediate Persistence
    
    /// Atomically writes the workspace topology to disk.
    ///
    /// Encodes to JSON, writes to `tempFileURL`, and performs an atomic POSIX `rename()`
    /// to `fileURL`, ensuring the file is never left in a corrupted or half-written state.
    public func saveImmediately(_ topology: WorkspaceTopology) throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingTopology = nil
        
        let directory = fileURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw WorkspacePersistenceError.directoryCreationFailed(error.localizedDescription)
            }
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data: Data
        do {
            data = try encoder.encode(topology)
        } catch {
            throw WorkspacePersistenceError.serializationFailed(error.localizedDescription)
        }
        
        // Step 1: Write to temporary file
        do {
            try data.write(to: tempFileURL)
        } catch {
            throw WorkspacePersistenceError.writeFailed("Failed writing to temporary file \(tempFileURL.path): \(error.localizedDescription)")
        }
        
        // Step 2: Atomic rename
        if Darwin.rename(tempFileURL.path, fileURL.path) != 0 {
            // Fallback to FileManager replaceItemAt if cross-volume or POSIX rename edge-case
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempFileURL)
                } else {
                    try fileManager.moveItem(at: tempFileURL, to: fileURL)
                }
            } catch {
                try? fileManager.removeItem(at: tempFileURL)
                throw WorkspacePersistenceError.writeFailed("Failed to atomically rename \(tempFileURL.path) to \(fileURL.path): \(error.localizedDescription)")
            }
        }
    }
    
    /// Records clean shutdown metadata and flushes immediately to disk.
    public func recordCleanShutdown(topology: WorkspaceTopology) throws {
        var shutdownTopology = topology
        shutdownTopology.cleanShutdown = true
        shutdownTopology.lastSavedAt = Date()
        try saveImmediately(shutdownTopology)
    }
    
    // MARK: - Loading & Crash Recovery
    
    /// Loads the persisted topology from disk if it exists.
    ///
    /// Throws an error if the file exists but contains invalid or corrupted JSON data.
    /// Returns `nil` if the persistence file does not exist yet.
    public func loadTopology() throws -> WorkspaceTopology? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw WorkspacePersistenceError.readFailed(error.localizedDescription)
        }
        
        guard !data.isEmpty else {
            throw WorkspacePersistenceError.corruptedData("File is empty (zero bytes)")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(WorkspaceTopology.self, from: data)
        } catch {
            throw WorkspacePersistenceError.deserializationFailed(error.localizedDescription)
        }
    }
    
    /// Loads the workspace topology with automated fallback recovery against corrupted files.
    ///
    /// If the file is missing, returns an empty clean topology with `wasCorrupted: false`.
    /// If the file is corrupted, creates a timestamped backup (`workspace.json.corrupted-<timestamp>`),
    /// cleans up the corrupted state, and returns an empty clean topology with `wasCorrupted: true`.
    public func loadWithRecovery() -> (topology: WorkspaceTopology, wasCorrupted: Bool) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return (WorkspaceTopology(), false)
        }
        
        do {
            if let loaded = try loadTopology() {
                return (loaded, false)
            } else {
                return (WorkspaceTopology(), false)
            }
        } catch {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupName = "workspace.json.corrupted-\(timestamp)"
            let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
            
            try? fileManager.moveItem(at: fileURL, to: backupURL)
            try? fileManager.removeItem(at: tempFileURL)
            
            return (WorkspaceTopology(), true)
        }
    }
    
    /// Clears any persisted workspace files (useful for test isolation or reset).
    public func clear() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: tempFileURL.path) {
            try fileManager.removeItem(at: tempFileURL)
        }
    }
}
