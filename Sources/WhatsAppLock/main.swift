import AppKit

// Entry point for the WhatsApp Lock menu bar utility.
// This is a plain executable (no storyboard/xib) that builds its whole UI in code.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu-bar-only app: no Dock icon, no app switcher entry.
app.setActivationPolicy(.accessory)

app.run()
