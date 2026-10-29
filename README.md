# LockGuard

Mantém o computador ativo e bloqueia-o automaticamente se alguém lhe tocar.

## Plataformas

- **macOS** — Swift (`macos/`). Build: `./macos/build_app.sh` e `./macos/build_dmg.sh`
- **Windows** — C# / .NET 8 (`windows/`). Build: `./windows/build_windows.sh`

## Instalação

Descarrega o instalador na [página de Releases](https://github.com/Pedrogoois/LockGuard/releases/latest).

### macOS

1. Abre o `LockGuard-Mac.dmg` e arrasta o **LockGuard** para **Applications**.
2. Na primeira vez que abrires a app, o macOS mostra *"LockGuard" Not Opened*. Isto acontece porque a app não está assinada com um Apple Developer ID. Clica **Done** e depois usa uma das opções abaixo.

**Opção 1: Definições do Sistema**

1. Abre **Definições do Sistema → Privacidade e Segurança**.
2. Na secção **Segurança**, clica **Abrir mesmo assim** ao lado da mensagem *"LockGuard" foi bloqueado*.
3. Confirma com a password ou o Touch ID.

**Opção 2: Terminal**

```sh
xattr -dr com.apple.quarantine /Applications/LockGuard.app
```

### Windows

1. Executa o `LockGuard-Windows.exe`. Não precisa de instalação.
2. Como o executável não está assinado, o SmartScreen pode mostrar *"O Windows protegeu o seu PC"*. Clica **Mais informações → Executar mesmo assim**.
