using System.Runtime.InteropServices;

namespace LockGuard;

public enum GuardState { Idle, Arming, Armed }

/// Vigia o input global e bloqueia a estação de trabalho quando armado.
public sealed class LockController
{
    public event Action? StateChanged;

    /// Segundos de tolerância depois de ativar, para o utilizador afastar-se.
    public int GracePeriod = 5;

    /// Movimento (em pixéis) do rato necessário para disparar o bloqueio.
    private const double MoveThreshold = 20;

    /// Intervalo (ms) entre micro-movimentos para manter o PC acordado.
    private const int JiggleInterval = 25000;

    /// Marca colocada nos eventos gerados pela própria app (para os ignorar).
    private static readonly UIntPtr SyntheticTag = (UIntPtr)0x4C474A47; // "LGJG"

    public GuardState State { get; private set; } = GuardState.Idle;
    public int Remaining { get; private set; }

    private readonly System.Windows.Forms.Timer _countdown = new() { Interval = 1000 };
    private readonly System.Windows.Forms.Timer _jiggle = new() { Interval = JiggleInterval };
    private double _accumulated;
    private int _lastX, _lastY;
    private bool _hasLast;

    /// Mantém o PC acordado e o Teams "disponível", independentemente da proteção.
    public bool KeepActive { get; private set; } = true;

    private IntPtr _mouseHook = IntPtr.Zero;
    private IntPtr _keyboardHook = IntPtr.Zero;
    private LowLevelProc? _mouseProc;
    private LowLevelProc? _keyboardProc;

    public LockController()
    {
        _countdown.Tick += OnTick;
        _jiggle.Tick += OnJiggle;
    }

    public bool IsActive => State != GuardState.Idle;

    // MARK: - Controlo público

    public void Toggle()
    {
        if (IsActive) Disarm(); else Arm();
    }

    /// Liga/desliga o "manter ativo" e aplica de imediato.
    public void SetKeepActive(bool on)
    {
        KeepActive = on;
        UpdateKeepAwake();
    }

    public void Arm()
    {
        _accumulated = 0;
        _hasLast = false;
        Remaining = GracePeriod;
        State = GuardState.Arming;
        StateChanged?.Invoke();
        _countdown.Start();
    }

    public void Disarm()
    {
        _countdown.Stop();
        StopHooks();
        State = GuardState.Idle;
        StateChanged?.Invoke();
        UpdateKeepAwake();
    }

    public void LockNow() => LockWorkStation();

    // MARK: - Contagem decrescente

    private void OnTick(object? sender, EventArgs e)
    {
        Remaining--;
        if (Remaining <= 0)
        {
            _countdown.Stop();
            BeginArmed();
        }
        else
        {
            StateChanged?.Invoke();
        }
    }

    private void BeginArmed()
    {
        _accumulated = 0;
        _hasLast = false;
        StartHooks();
        UpdateKeepAwake();
        State = GuardState.Armed;
        StateChanged?.Invoke();
    }

    private void Trigger()
    {
        StopHooks();
        _countdown.Stop();
        State = GuardState.Idle;
        StateChanged?.Invoke();
        UpdateKeepAwake();
        LockWorkStation();
    }

    // MARK: - Hooks de baixo nível (rato + teclado)

    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;
    private const int WM_MOUSEMOVE = 0x0200;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;

    private delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool LockWorkStation();

    private void StartHooks()
    {
        _mouseProc = MouseHookCallback;
        _keyboardProc = KeyboardHookCallback;
        IntPtr hMod = GetModuleHandle(null);
        _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, hMod, 0);
        _keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, hMod, 0);
    }

    private void StopHooks()
    {
        if (_mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_mouseHook);
            _mouseHook = IntPtr.Zero;
        }
        if (_keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }
        _mouseProc = null;
        _keyboardProc = null;
    }

    private const uint LLMHF_INJECTED = 0x00000001;

    private IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && State == GuardState.Armed)
        {
            var data = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            bool synthetic = (data.flags & LLMHF_INJECTED) != 0
                             || (ulong)data.dwExtraInfo == (ulong)SyntheticTag;
            if (!synthetic)
            {
                int msg = (int)wParam;
                if (msg == WM_MOUSEMOVE)
                {
                    if (_hasLast)
                    {
                        _accumulated += Math.Abs(data.pt.x - _lastX) + Math.Abs(data.pt.y - _lastY);
                    }
                    _lastX = data.pt.x;
                    _lastY = data.pt.y;
                    _hasLast = true;
                    if (_accumulated >= MoveThreshold)
                    {
                        Trigger();
                    }
                }
                else
                {
                    // Clique ou scroll → bloqueia de imediato.
                    Trigger();
                }
            }
        }
        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && State == GuardState.Armed)
        {
            int msg = (int)wParam;
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                Trigger();
            }
        }
        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    // MARK: - Manter acordado + jiggle

    private void OnJiggle(object? sender, EventArgs e) => PostJiggle();

    /// Decide se o keep-awake deve estar a correr (ativo manual OU armado).
    private void UpdateKeepAwake()
    {
        bool shouldRun = KeepActive || State == GuardState.Armed;
        if (shouldRun) StartKeepAwake(); else StopKeepAwake();
    }

    private void StartKeepAwake()
    {
        SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS
                                | EXECUTION_STATE.ES_SYSTEM_REQUIRED
                                | EXECUTION_STATE.ES_DISPLAY_REQUIRED);
        if (!_jiggle.Enabled)
        {
            _jiggle.Start();
            PostJiggle(); // dispara já um
        }
    }

    private void StopKeepAwake()
    {
        _jiggle.Stop();
        SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
    }

    /// Mexe o cursor 1px e volta, marcando os eventos como sintéticos.
    private void PostJiggle()
    {
        SendRelativeMove(1, 0);
        SendRelativeMove(-1, 0);
        _accumulated = 0;
    }

    private void SendRelativeMove(int dx, int dy)
    {
        var input = new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = dx,
                    dy = dy,
                    mouseData = 0,
                    dwFlags = MOUSEEVENTF_MOVE,
                    time = 0,
                    dwExtraInfo = SyntheticTag
                }
            }
        };
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    private const uint INPUT_MOUSE = 0;
    private const uint MOUSEEVENTF_MOVE = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [Flags]
    private enum EXECUTION_STATE : uint
    {
        ES_CONTINUOUS = 0x80000000,
        ES_SYSTEM_REQUIRED = 0x00000001,
        ES_DISPLAY_REQUIRED = 0x00000002
    }

    [DllImport("kernel32.dll")]
    private static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);
}
