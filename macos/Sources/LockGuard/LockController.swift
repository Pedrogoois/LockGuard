import Cocoa
import ApplicationServices
import IOKit.pwr_mgt

/// Estados possíveis da proteção.
enum GuardState {
    case idle                       // desligado
    case arming(remaining: Int)     // contagem decrescente antes de armar
    case armed                      // vigilância ativa
}

/// Controla a vigilância de input e o bloqueio do ecrã.
final class LockController {

    var onStateChange: (() -> Void)?

    /// Segundos de tolerância depois de ativar, para o utilizador afastar-se sem disparar.
    var gracePeriod = 5

    /// Movimento (em pontos) do rato necessário para disparar o bloqueio.
    private let moveThreshold: CGFloat = 20

    /// Intervalo (segundos) entre micro-movimentos para manter o Mac acordado.
    private let jiggleInterval: TimeInterval = 20

    /// Etiqueta que marca os eventos gerados pela própria app (para os ignorar).
    private let syntheticTag: Int64 = 0x4C47_4A47 // "LGJG"

    /// Mantém o Mac acordado e o Teams "disponível", independentemente da proteção.
    var keepActive = true {
        didSet { updateKeepAwake() }
    }

    private(set) var state: GuardState = .idle {
        didSet { onStateChange?() }
    }

    private var monitor: Any?
    private var countdownTimer: Timer?
    private var jiggleTimer: Timer?
    private var accumulatedMovement: CGFloat = 0
    private var sleepAssertionID: IOPMAssertionID = 0
    private var hasSleepAssertion = false
    private var userActivityID: IOPMAssertionID = 0

    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    // MARK: - Controlo público

    func toggle() {
        isActive ? disarm() : arm()
    }

    /// Liga/desliga o "manter ativo" e aplica de imediato.
    func setKeepActive(_ on: Bool) {
        keepActive = on
    }

    func arm() {
        ensureAccessibilityPermission()
        accumulatedMovement = 0
        startCountdown()
    }

    func disarm() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        stopMonitoring()
        state = .idle
        updateKeepAwake()
    }

    func lockNow() {
        LockController.lockScreen()
    }

    // MARK: - Contagem decrescente

    private func startCountdown() {
        var remaining = gracePeriod
        state = .arming(remaining: remaining)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.beginArmed()
            } else {
                self.state = .arming(remaining: remaining)
            }
        }
    }

    private func beginArmed() {
        accumulatedMovement = 0
        startMonitoring()
        updateKeepAwake()
        state = .armed
    }

    // MARK: - Vigilância de input

    private func startMonitoring() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .scrollWheel,
            .keyDown, .flagsChanged
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard case .armed = state else { return }
        // Ignora os micro-movimentos gerados pela própria app.
        if let cg = event.cgEvent, cg.getIntegerValueField(.eventSourceUserData) == syntheticTag {
            return
        }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            accumulatedMovement += abs(event.deltaX) + abs(event.deltaY)
            if accumulatedMovement >= moveThreshold {
                triggerLock()
            }
        default:
            // Tecla, clique ou scroll → bloqueia de imediato.
            triggerLock()
        }
    }

    private func triggerLock() {
        stopMonitoring()
        countdownTimer?.invalidate()
        countdownTimer = nil
        state = .idle
        updateKeepAwake()
        LockController.lockScreen()
    }

    // MARK: - Manter acordado + jiggle

    /// Decide se o keep-awake deve estar a correr (ativo manual OU armado).
    private func updateKeepAwake() {
        var shouldRun = keepActive
        if case .armed = state { shouldRun = true }
        if shouldRun {
            if keepActive { ensureAccessibilityPermission() }
            startKeepAwake()
        } else {
            stopKeepAwake()
        }
    }

    private func startKeepAwake() {
        preventSleep()
        guard jiggleTimer == nil else { return }
        jiggleTimer = Timer.scheduledTimer(withTimeInterval: jiggleInterval, repeats: true) { [weak self] _ in
            self?.postJiggle()
        }
        postJiggle() // dispara já um, para não esperar o primeiro intervalo
    }

    private func stopKeepAwake() {
        jiggleTimer?.invalidate()
        jiggleTimer = nil
        allowSleep()
    }

    /// Mexe o cursor 1px e volta, marcando os eventos como sintéticos,
    /// e declara atividade do utilizador (reforça a presença "disponível").
    private func postJiggle() {
        IOPMAssertionDeclareUserActivity("LockGuard keep active" as CFString,
                                         kIOPMUserActiveLocal,
                                         &userActivityID)
        let current = CGEvent(source: nil)?.location ?? .zero
        postSyntheticMove(to: CGPoint(x: current.x + 1, y: current.y))
        postSyntheticMove(to: current)
        // Segurança: evita que qualquer evento sintético residual se acumule.
        accumulatedMovement = 0
    }

    private func postSyntheticMove(to point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    private func preventSleep() {
        guard !hasSleepAssertion else { return }
        let reason = "LockGuard armado" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
        hasSleepAssertion = (result == kIOReturnSuccess)
    }

    private func allowSleep() {
        if hasSleepAssertion {
            IOPMAssertionRelease(sleepAssertionID)
            hasSleepAssertion = false
        }
    }

    // MARK: - Bloqueio do ecrã

    static func lockScreen() {
        // Método principal: API privada de login.framework que mostra o ecrã de bloqueio.
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockFn = @convention(c) () -> Void
            let fn = unsafeBitCast(sym, to: LockFn.self)
            fn()
            return
        }
        // Fallback: adormecer o ecrã (bloqueia se estiver definido pedir password).
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    // MARK: - Permissão de Acessibilidade

    @discardableResult
    private func ensureAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
