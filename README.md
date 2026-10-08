# Eye

Vigia o Mac pela webcam. Se ninguém aparece na câmera por um tempo, cobre a tela com um olho de dragão
que segue com a pupila quem passar na frente. Para sair, digite a senha do macOS e aperte Enter, ou use a digital (Touch ID).

## Rodar

    ./build.sh
    open /Applications/Eye.app

O `build.sh` instala em `/Applications` toda vez (e reabre o Eye se ele estava aberto). Pra só compilar: `NO_INSTALL=1 ./build.sh`.

O app fica só na barra de menus (ícone de olho). Na primeira vez o macOS pede permissão para a câmera.

## Menu

- **Vigiar**: liga/desliga o bloqueio automático
- **Bloquear agora** / **Mostrar o olho (prévia)**: mostra o olho numa janela normal, sem bloquear
- **Bloquear após ausência de**: 1s a 5min (padrão 1s)
- **Câmera**: escolhe qual webcam usar
- **Espelhar câmera**: troque se o olho olhar pro lado errado
- **Modo teste**: enquanto estiver ligado, Forçar Encerrar (⌥⌘⎋) funciona com a tela bloqueada (rota de fuga)
- **Abrir ao iniciar sessão**

## Como funciona

- `PresenceDetector`: AVFoundation + Vision (rosto; a parte de cima do corpo só guia o olhar), ~10x/s. Só rosto conta como presença
- `LockOverlay`: janela em nível de proteção de tela em cada monitor + modo quiosque (sem Dock, menu, ⌘Tab)
- `DragonEye` / `Art`: o olho é procedural (Core Graphics + Core Animation); dá pra trocar pela sua arte depois
- `Auth`: confere a senha do usuário logado via OpenDirectory, ou a senha secreta do Eye (só o hash PBKDF2 fica no código)
- Touch ID: `LAAuthenticationView` dentro da tela de bloqueio (o diálogo do sistema ficaria escondido atrás dela); depois de muitas digitais erradas o macOS exige a senha
- Sem imagem da câmera (tampa fechada, câmera ocupada) ele nunca bloqueia

Ícone: `Resources/AppIcon.icns`, gerado do próprio olho com `build/Eye.app/Contents/MacOS/Eye --icon icone.png` (1024×1024) e depois `sips` + `iconutil`.

Para conferir a arte sem abrir nada: `build/Eye.app/Contents/MacOS/Eye --snapshot olho.png -0.5,0.2`
