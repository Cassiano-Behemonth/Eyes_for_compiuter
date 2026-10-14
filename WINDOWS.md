# Eye no Windows: o que foi feito e como rodar

Este arquivo resume o que foi montado na branch `windows` e como colocar tudo para funcionar do zero.

## Visão geral

O Eye no Windows é um servidor Python (`app.py`) que lê a webcam com OpenCV e serve uma página (`web/`) com o olho. O olho segue o rosto pela câmera. Se ninguém aparecer por um tempo que você define, o Windows mostra o olho em tela cheia (protetor de tela seguro) e, ao voltar, pede a sua senha normal.

    webcam ──> app.py (OpenCV, detecta rosto) ──> /api/presence ──> web/ (olho no Edge)
                   │
                   └─ vigia de ausência ──> dispara o protetor Eye.scr ──> Windows pede a senha

## Como fizemos rodar (passo a passo)

1. **Python 3.12** instalado com `winget install Python.Python.3.12`. O Windows só tinha o atalho da Microsoft Store, que não roda nada.
2. **Dependências:** `pip install -r requirements.txt` (`opencv-python<5` e `numpy`).
   - O `<5` é importante: o OpenCV 5.0 tirou o `CascadeClassifier` do pacote principal. Sem ele a thread da câmera morria em silêncio e o servidor ficava de pé sem câmera.
3. **Iniciar:** dê dois cliques em `iniciar.bat` (ou `python app.py`) e abra `http://127.0.0.1:54321`. Mexa o mouse para o menu aparecer e clique no 📷 para ver a prévia da câmera.

## Bloqueio por ausência

No menu da página (aparece ao mexer o mouse):

- **🔓/🔒:** liga ou desliga a vigia (começa desligada).
- **Seletor de tempo:** 1s, 3s, 5s, 10s, 15s, 30s, 1min, 2min, 5min, 10min ou 30min (padrão 30s).

A escolha é salva em `eye_config.json` (ignorado pelo git) e vale mesmo com a página fechada, porque quem vigia é o servidor.

Regras da vigia (`app.py`, função `_absence_watcher`):

- Só bloqueia depois de ter visto um rosto. Não bloqueia logo que o app abre.
- Depois de bloquear, só bloqueia de novo depois de ver um rosto outra vez.
- Sem imagem da câmera (desligada, ocupada, travada), nunca bloqueia.

## Como o "olho sobre o bloqueio" funciona

A tela de bloqueio real do Windows roda num desktop seguro e nenhum programa consegue desenhar sobre ela. Por isso usamos o **protetor de tela seguro**:

1. Sem rosto pelo tempo escolhido, o servidor envia `SC_SCREENSAVE` ao Windows, que inicia o `Eye.scr`.
2. O `Eye.scr` sobe o servidor se preciso, cobre a tela e abre o Edge em modo quiosque com o olho. Ele **fica vivo** enquanto não houver atividade.
3. Ao mexer o mouse ou o teclado, ele fecha o Edge e chama `LockWorkStation`. O Windows mostra o login normal (senha, PIN ou digital).
4. Se o `Eye.scr` não for o protetor ativo e seguro, o servidor bloqueia o Windows direto, sem o olho.

Pontos que deram trabalho:

- A versão original do `Eye.scr` abria o Edge e encerrava na hora. Num protetor seguro isso faria o Windows bloquear imediatamente e esconder o olho. Foi reescrito (`windows/Eye.cs`) para ficar vivo e detectar atividade com `GetLastInputInfo`.
- Ao sair do protetor disparado por `SC_SCREENSAVE`, o Windows **não** bloqueou sozinho. Por isso o próprio `.scr` chama `LockWorkStation` ao sair, se `ScreenSaverIsSecure=1`.
- O `.scr` grava o motivo da saída em `%TEMP%\eye_scr.log`, útil para depurar.

## Câmera só sob demanda

O servidor pode ficar sempre ligado sem manter a webcam acesa. A câmera só abre quando:

- a vigia está ligada, ou
- a página do olho está aberta (consultando `/api/presence`, `/api/presence_stream`, `/api/camera_snapshot` ou `/api/camera_feed`).

Sem demanda por cerca de 5s, ela é liberada.

## Instalação do protetor e início automático

Dê dois cliques em `instalar_protetor_de_tela.bat`. Ele:

- recompila o `Eye.scr` (`compilar_scr.bat`, usa o `csc.exe` do .NET Framework, não precisa instalar nada);
- define o `Eye.scr` como protetor ativo (`SCRNSAVE.EXE`, `ScreenSaveActive=1`);
- liga "Ao reiniciar, exibir tela de logon" (`ScreenSaverIsSecure=1`);
- registra o caminho do projeto (`HKCU\Software\EyeScreensaver`);
- registra o servidor para iniciar com o login (`HKCU\...\Run`, valor `EyeServer`).

Efeito colateral: como o Eye é o protetor do Windows, ele também aparece pelo tempo de inatividade do sistema.

### Desfazer

- Troque o protetor em Configurações > Personalização > Tela de bloqueio > Proteção de tela.
- Apague o valor `EyeServer` em `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- Para parar agora: encerre o `python`/`pythonw` que roda o `app.py`.

## Mapa dos arquivos

| Arquivo | Para que serve |
|---|---|
| `app.py` | Servidor HTTP, rastreio de rosto (OpenCV), vigia de ausência, API `/api/config` |
| `web/` | Página do olho, menu, seletor de tempo e cadeado |
| `windows/Eye.cs` | Fonte do `Eye.scr` (protetor de tela) |
| `Eye.scr` | Protetor compilado |
| `compilar_scr.bat` | Recompila o `Eye.scr` |
| `instalar_protetor_de_tela.bat` | Configura protetor seguro e início automático |
| `iniciar.bat` | Sobe o servidor e abre o olho em tela cheia |
| `requirements.txt` | Dependências Python |
| `eye_config.json` | Configuração da vigia (criado sozinho, fora do git) |

## API local

- `GET /api/config`: `{watch, lock_after, options}`
- `POST /api/config`: JSON com `watch` (bool) e/ou `lock_after` (segundos, 1 a 86400)
- `GET /api/presence`: `{detected, x, y, closeness, camera_active, ...}`

## Limites conhecidos

- O olho aparece **antes** do login. A tela de login em si continua sendo a do Windows.
- A webcam usa o índice 0; com mais de uma câmera, não há seletor ainda.
- A detecção usa classificadores Haar. Em pouca luz ou de perfil, pode falhar por instantes.
- O rastreio e a lógica da vigia foram testados. O fluxo completo com a câmera tampada até o bloqueio real foi verificado por partes (a vigia por simulação, o protetor e o bloqueio com o Windows de verdade).
