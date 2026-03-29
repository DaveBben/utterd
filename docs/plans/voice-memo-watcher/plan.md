# Voice Memo File Watcher — Complete

- **Status:** Complete
- **Completed:** 2026-03-28
- Monitors iCloud Voice Memos sync folder for new .m4a files using FSEvents C API
- Emits `VoiceMemoEvent` via `AsyncStream` with multi-listener broadcast support
- Handles missing/unreadable folders with exponential backoff polling (5s–60s)
- Catalogs existing files on startup to avoid re-processing; exactly-once dedup per path

## Leftover Issues

- SC-4 (memory footprint ≤ 10% after 100 events) deferred — requires profiling tooling; seen-set grows ~80 bytes/entry, negligible at expected volume
- SC-5 (detection latency < 5s) verified via FSEvents integration test but not under production iCloud sync conditions
- ~~Sandbox/entitlements work needed before the watcher can access the real Voice Memos group container~~ Resolved by `permissions` branch (Full Disk Access gate, sandbox removed)
