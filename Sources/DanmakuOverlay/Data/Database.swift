import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 本地 SQLite 存储（需求文档 10.3 节表结构）
final class Database {
    static let shared = Database()

    private var db: OpaquePointer?

    /// Application Support/DanmakuOverlay/
    static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DanmakuOverlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var cacheDir: URL {
        let dir = appSupportDir.appendingPathComponent("danmaku_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        let path = Self.appSupportDir.appendingPathComponent("danmaku_overlay.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("Database: failed to open \(path)")
        }
        createTables()
    }

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS video_sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bvid TEXT NOT NULL,
            aid INTEGER,
            cid INTEGER NOT NULL,
            page INTEGER DEFAULT 1,
            title TEXT,
            part_title TEXT,
            owner TEXT,
            duration INTEGER,
            danmaku_count INTEGER,
            last_opened_at REAL,
            UNIQUE(bvid, cid)
        );
        CREATE TABLE IF NOT EXISTS external_targets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_source_id INTEGER REFERENCES video_sources(id),
            note TEXT
        );
        CREATE TABLE IF NOT EXISTS danmaku_cache (
            cid INTEGER PRIMARY KEY,
            file_path TEXT NOT NULL,
            count INTEGER,
            fetched_at REAL
        );
        CREATE TABLE IF NOT EXISTS sync_profiles (
            cid INTEGER PRIMARY KEY,
            offset_seconds REAL DEFAULT 0,
            rate REAL DEFAULT 1.0,
            updated_at REAL
        );
        CREATE TABLE IF NOT EXISTS filters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,       -- keyword | regex | color | length
            value TEXT NOT NULL,
            enabled INTEGER DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """)
    }

    // MARK: - video_sources / 历史记录

    struct HistoryEntry {
        var bvid: String
        var cid: Int64
        var page: Int
        var title: String
        var partTitle: String
        var owner: String
        var danmakuCount: Int
        var lastOpenedAt: Date
    }

    func recordVideo(info: VideoInfo, page: VideoPage) {
        run("""
        INSERT INTO video_sources (bvid, aid, cid, page, title, part_title, owner, duration, danmaku_count, last_opened_at)
        VALUES (?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(bvid, cid) DO UPDATE SET
            aid = excluded.aid,
            page = excluded.page,
            title = excluded.title,
            part_title = excluded.part_title,
            owner = excluded.owner,
            duration = excluded.duration,
            danmaku_count = excluded.danmaku_count,
            last_opened_at = excluded.last_opened_at
        """, [.text(info.bvid), .int(info.aid), .int(page.cid), .int(Int64(page.page)),
              .text(info.title), .text(page.title), .text(info.owner),
              .int(Int64(info.duration)), .int(Int64(info.danmakuCount)),
              .real(Date().timeIntervalSince1970)])
    }

    func recentVideos(limit: Int = 20) -> [HistoryEntry] {
        query("""
        SELECT bvid, cid, page, title, part_title, owner, danmaku_count, last_opened_at
        FROM video_sources ORDER BY last_opened_at DESC LIMIT \(limit)
        """).map { row in
            HistoryEntry(bvid: row[0] as? String ?? "",
                         cid: row[1] as? Int64 ?? 0,
                         page: Int(row[2] as? Int64 ?? 1),
                         title: row[3] as? String ?? "",
                         partTitle: row[4] as? String ?? "",
                         owner: row[5] as? String ?? "",
                         danmakuCount: Int(row[6] as? Int64 ?? 0),
                         lastOpenedAt: Date(timeIntervalSince1970: row[7] as? Double ?? 0))
        }
    }

    // MARK: - 弹幕缓存

    func cachedDanmakuPath(cid: Int64) -> URL? {
        let rows = query("SELECT file_path FROM danmaku_cache WHERE cid = \(cid)")
        guard let p = rows.first?.first as? String,
              FileManager.default.fileExists(atPath: p) else { return nil }
        return URL(fileURLWithPath: p)
    }

    func saveDanmakuCache(cid: Int64, list: [Danmaku]) {
        let url = Self.cacheDir.appendingPathComponent("\(cid).json")
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url)
            run("INSERT OR REPLACE INTO danmaku_cache (cid, file_path, count, fetched_at) VALUES (?,?,?,?)",
                [.int(cid), .text(url.path), .int(Int64(list.count)), .real(Date().timeIntervalSince1970)])
        }
    }

    func loadDanmakuCache(cid: Int64) -> [Danmaku]? {
        guard let url = cachedDanmakuPath(cid: cid),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Danmaku].self, from: data) else { return nil }
        return list
    }

    // MARK: - 时间轴同步方案

    func saveSyncProfile(cid: Int64, offset: Double, rate: Double) {
        run("INSERT OR REPLACE INTO sync_profiles (cid, offset_seconds, rate, updated_at) VALUES (?,?,?,?)",
            [.int(cid), .real(offset), .real(rate), .real(Date().timeIntervalSince1970)])
    }

    func loadSyncProfile(cid: Int64) -> (offset: Double, rate: Double)? {
        let rows = query("SELECT offset_seconds, rate FROM sync_profiles WHERE cid = \(cid)")
        guard let row = rows.first else { return nil }
        return (row[0] as? Double ?? 0, row[1] as? Double ?? 1.0)
    }

    // MARK: - settings KV

    func setSetting(_ key: String, _ value: String) {
        run("INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)", [.text(key), .text(value)])
    }

    func getSetting(_ key: String) -> String? {
        query("SELECT value FROM settings WHERE key = '\(key.replacingOccurrences(of: "'", with: "''"))'")
            .first?.first as? String
    }

    // MARK: - SQLite 底层

    enum Value {
        case text(String), int(Int64), real(Double)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("Database exec error: \(String(cString: err))")
            sqlite3_free(err)
        }
    }

    @discardableResult
    private func run(_ sql: String, _ values: [Value]) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Database prepare error: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            }
        }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func query(_ sql: String) -> [[Any?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Database query error: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [[Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [Any?] = []
            for col in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, col) {
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(stmt, col)))
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(stmt, col))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(stmt, col))
                default: row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }
}
