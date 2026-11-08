import os

/// `log stream --level debug --predicate 'subsystem == "com.dric.VimE"'` to watch.
enum Log {
    static let keys = Logger(subsystem: "com.dric.VimE", category: "keys")
}
