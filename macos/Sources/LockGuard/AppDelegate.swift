import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let controller = LockController()
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var keepActiveMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        controller.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.updateUI() }
        }
        buildMenu()
        controller.setKeepActive(true) // arranca a manter o Teams ativo
        updateUI()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Estado: Inativo", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "Ativar proteção", action: #selector(toggleProtection), keyEquivalent: "a")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        let lockNow = NSMenuItem(title: "Bloquear agora", action: #selector(lockNowAction), keyEquivalent: "l")
        lockNow.target = self
        menu.addItem(lockNow)

        menu.addItem(.separator())

        keepActiveMenuItem = NSMenuItem(title: "Manter ativo", action: #selector(toggleKeepActive), keyEquivalent: "")
        keepActiveMenuItem.target = self
        keepActiveMenuItem.state = controller.keepActive ? .on : .off
        menu.addItem(keepActiveMenuItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Sair", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleProtection() { controller.toggle() }
    @objc private func lockNowAction() { controller.lockNow() }
    @objc private func toggleKeepActive() {
        controller.setKeepActive(!controller.keepActive)
        keepActiveMenuItem.state = controller.keepActive ? .on : .off
    }
    @objc private func quitAction() { NSApplication.shared.terminate(nil) }

    // MARK: - UI

    private func updateUI() {
        guard let button = statusItem.button else { return }
        switch controller.state {
        case .idle:
            button.image = symbol("lock.open", "LockGuard inativo")
            statusMenuItem.title = "Estado: Inativo"
            toggleMenuItem.title = "Ativar proteção"
        case .arming(let remaining):
            button.image = symbol("hourglass", "A armar")
            statusMenuItem.title = "A armar em \(remaining)s… (afasta-te)"
            toggleMenuItem.title = "Cancelar"
        case .armed:
            button.image = symbol("lock.shield.fill", "Armado")
            statusMenuItem.title = "ARMADO — vigilância ativa"
            toggleMenuItem.title = "Desativar proteção"
        }
    }

    private func symbol(_ name: String, _ desc: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: desc)
        img?.isTemplate = true
        return img
    }
}
