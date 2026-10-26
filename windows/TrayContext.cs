using System.Drawing;
using System.Windows.Forms;

namespace LockGuard;

public sealed class TrayContext : ApplicationContext
{
    private readonly NotifyIcon _icon;
    private readonly LockController _controller = new();
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _toggleItem;
    private readonly ToolStripMenuItem _keepActiveItem;

    public TrayContext()
    {
        _statusItem = new ToolStripMenuItem("Estado: Inativo") { Enabled = false };
        _toggleItem = new ToolStripMenuItem("Ativar protecao", null, (_, _) => _controller.Toggle());
        var lockNow = new ToolStripMenuItem("Bloquear agora", null, (_, _) => _controller.LockNow());
        _keepActiveItem = new ToolStripMenuItem("Manter ativo", null, (_, _) => ToggleKeepActive())
        {
            Checked = _controller.KeepActive
        };
        var quit = new ToolStripMenuItem("Sair", null, (_, _) => ExitThread());

        var menu = new ContextMenuStrip();
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_toggleItem);
        menu.Items.Add(lockNow);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_keepActiveItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(quit);

        _icon = new NotifyIcon
        {
            Icon = SystemIcons.Shield,
            Visible = true,
            Text = "LockGuard",
            ContextMenuStrip = menu
        };

        _controller.StateChanged += UpdateUI;
        _controller.SetKeepActive(true); // arranca a manter o Teams ativo
        UpdateUI();
    }

    private void ToggleKeepActive()
    {
        _controller.SetKeepActive(!_controller.KeepActive);
        _keepActiveItem.Checked = _controller.KeepActive;
    }

    private void UpdateUI()
    {
        switch (_controller.State)
        {
            case GuardState.Idle:
                _statusItem.Text = "Estado: Inativo";
                _toggleItem.Text = "Ativar protecao";
                _icon.Icon = SystemIcons.Shield;
                _icon.Text = "LockGuard - Inativo";
                break;
            case GuardState.Arming:
                _statusItem.Text = $"A armar em {_controller.Remaining}s... (afasta-te)";
                _toggleItem.Text = "Cancelar";
                _icon.Text = "LockGuard - A armar";
                break;
            case GuardState.Armed:
                _statusItem.Text = "ARMADO - vigilancia ativa";
                _toggleItem.Text = "Desativar protecao";
                _icon.Icon = SystemIcons.Warning;
                _icon.Text = "LockGuard - ARMADO";
                break;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _icon.Visible = false;
            _icon.Dispose();
        }
        base.Dispose(disposing);
    }
}
