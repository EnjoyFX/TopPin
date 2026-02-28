import AppKit

// Entry point – must be in main.swift (not @main annotated type)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
