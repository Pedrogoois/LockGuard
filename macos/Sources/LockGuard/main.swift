import Cocoa

// LockGuard corre apenas na barra de menus (sem ícone no Dock).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
