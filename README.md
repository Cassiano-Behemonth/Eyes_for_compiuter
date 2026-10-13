# Eye

Vigia o computador pela webcam. Se ninguém aparece na câmera por um tempo, cobre a tela com um olho de dragão
que segue com a pupila quem passar na frente. Para sair, digite a senha do macOS e aperte Enter, ou use a digital (Touch ID).

Hoje o Eye roda **só no macOS** (14 ou mais novo). Para Windows, veja [Windows](#windows) no fim deste arquivo.

## Rodar (macOS)

    ./build.sh
    open /Applications/Eye.app

O `build.sh` instala em `/Applications` toda vez (e reabre o Eye se ele estava aberto). Pra só compilar: `NO_INSTALL=1 ./build.sh`.

O app fica só na barra de menus (ícone de olho). Na primeira vez o macOS pede permissão para a câmera.

## Menu

- **Vigiar**: liga/desliga o bloqueio automático
- **Bloquear agora** / **Mostrar o olho (prévia)**: mostra o olho numa janela normal, sem bloquear
- **Bloquear após ausência de**: 1s a 5min (padrão 1s)
- **Câmera**: escolhe qual webcam usar
- **Tema**: troca a cara do olho (veja [Temas](#temas)); **Abrir pasta de temas…** abre a pasta dos seus
- **Espelhar câmera**: troque se o olho olhar pro lado errado
- **Modo teste**: enquanto estiver ligado, Forçar Encerrar (⌥⌘⎋) funciona com a tela bloqueada (rota de fuga)
- **Abrir ao iniciar sessão**

## Temas

Já vêm quatro: **Dragão** (o padrão), **Gelo**, **Veneno** e **Sombra**. A escolha fica salva.

### Criar o seu

Cada tema é uma pasta dentro de:

    ~/Library/Application Support/Eye/Temas/

O nome da pasta é o nome que aparece no menu. Dentro dela, todos os arquivos são opcionais (mas precisa ter pelo menos um):

| Arquivo        | O que faz |
|----------------|-----------|
| `tema.json`    | Cores do olho (abaixo) |
| `iris.png`     | Imagem da íris. Quadrada, com a íris ocupando o quadrado todo e **sem pupila**: a pupila de fenda é desenhada por cima e se mexe. A borda é escurecida pra encaixar no olho |
| `esclera.png`  | O fundo do olho, atrás da íris. Proporção ~1,8:1 (larga) |
| `pele.png`     | O fundo da tela inteira, no lugar das escamas. Proporção da tela (ex.: 16:10). O olho é desenhado no centro, um pouco acima do meio |

As imagens cobrem a área toda sem distorcer: o que sobrar nas bordas é cortado. Use PNG grande (2× o tamanho da tela) para ficar nítido em tela Retina.

Exemplo de `tema.json` (está pronto em [`Exemplos/Temas/Lava`](Exemplos/Temas/Lava/tema.json)):

```json
{
  "base": "Dragão",
  "iris": ["#ffffff", "#fff27a", "#ffb000", "#ff5a00", "#a01000", "#300000"],
  "fibras": ["#fff6b0", "#ff8a00", "#400800"],
  "esclera": ["#ff6a00", "#7a1400", "#1a0200"],
  "veias": "#ffb030",
  "escamas": "#3a3030",
  "brilho": "#ff7a00",
  "destaque": "#ffb04a"
}
```

| Chave      | O que é |
|------------|---------|
| `base`     | Tema pronto de onde vem tudo que você não definir (`Dragão`, `Gelo`, `Veneno` ou `Sombra`; padrão `Dragão`) |
| `iris`     | Degradê da íris, do centro para a borda (2 ou mais cores; com 6 fica igual ao Dragão) |
| `fibras`   | 3 cores das fibras da íris: clara, média, escura (a escura também faz as manchas e o anel da borda) |
| `esclera`  | Degradê do fundo do olho, do centro para a borda (2 ou mais) |
| `veias`    | Cor das veias no fundo do olho |
| `escamas`  | Cor das escamas e pálpebras na parte mais iluminada; as sombras saem dela |
| `brilho`   | Brilho em volta do olho e da raiva |
| `destaque` | Pontinhos da senha e o texto embaixo |

Cores em `#rrggbb`. Se o `tema.json` tiver erro, o Eye usa o tema `base` e registra o erro no Console (procure por `Eye: tema.json inválido`).
Uma pasta com o mesmo nome de um tema pronto substitui o pronto.

Para usar o exemplo:

    cp -R Exemplos/Temas/Lava ~/Library/Application\ Support/Eye/Temas/

Depois de mudar os arquivos de um tema, escolha ele de novo no menu **Tema** pra recarregar. Com a prévia aberta, a troca aparece na hora.

Para ver um tema sem abrir nada (o `--tema` vem antes do `--snapshot`):

    build/Eye.app/Contents/MacOS/Eye --tema Lava --snapshot olho.png -0.5,0.2

## Como funciona

- `PresenceDetector`: AVFoundation + Vision (rosto; a parte de cima do corpo só guia o olhar), ~10x/s. Só rosto conta como presença. Se a câmera cair, troca sozinho pra outra e volta quando ela reconectar
- `LockOverlay`: janela em nível de proteção de tela em cada monitor + modo quiosque (sem Dock, menu, ⌘Tab). Pausa o que estiver tocando
- `DragonEye` / `Art`: o olho é procedural (Core Graphics + Core Animation). As texturas são desenhadas antes, em segundo plano, pro bloqueio aparecer na hora
- `Theme`: temas prontos e os da pasta do usuário
- `Auth`: confere a senha do usuário logado via OpenDirectory, ou a senha secreta do Eye (só o hash PBKDF2 fica no código)
- Touch ID: `LAAuthenticationView` dentro da tela de bloqueio (o diálogo do sistema ficaria escondido atrás dela); depois de muitas digitais erradas o macOS exige a senha
- Sem imagem da câmera (tampa fechada, câmera ocupada) ele nunca bloqueia

Ícone: `Resources/AppIcon.icns`, gerado do próprio olho com `build/Eye.app/Contents/MacOS/Eye --icon icone.png` (1024×1024) e depois `sips` + `iconutil`.

Para conferir a arte sem abrir nada: `build/Eye.app/Contents/MacOS/Eye --snapshot olho.png -0.5,0.2`

## Windows

**Ainda não existe versão para Windows.** O código daqui é todo nativo do macOS (AppKit, AVFoundation, Vision,
OpenDirectory, Touch ID) e não compila no Windows. Fazer o Eye no Windows é escrever um app novo.

### Como fazer o port

Quem for fazer (pessoa ou IA) **não deve traduzir este código arquivo por arquivo**. O caminho é:

1. **Analisar primeiro.** Ler os fontes em `Sources/` e entender *o que* o Eye faz e *por quê*. Muitas decisões aqui
   resolvem problemas que são do macOS (App Nap, Spaces de tela cheia, o diálogo do Touch ID ficar escondido atrás
   da janela) e não existem no Windows. O Windows tem os problemas dele, que o Mac não tem.
2. **Pensar a estrutura do zero.** Com o comportamento entendido, desenhar a arquitetura que faz mais sentido no
   Windows: linguagem, framework de interface, como dividir em módulos, o que dá pra compartilhar entre os dois
   sistemas. Não copiar a estrutura do Mac só porque ela existe; se aparecer um jeito melhor, ele vale (e pode até
   voltar para a versão Mac depois).
3. **Escrever a proposta antes do código.** Um documento curto com a estrutura escolhida, as alternativas
   descartadas e o motivo, e os riscos. Depois disso, implementar.

### O que o Eye precisa fazer (o comportamento, não o código)

- Ficar na bandeja do sistema, sem janela, com um menu com as mesmas opções do Mac
- Ler a webcam ~10x por segundo, achar rosto (presença) e a posição da pessoa (pra onde o olho olha)
- Sem rosto por X segundos → bloquear. Sem imagem da câmera → **nunca** bloquear
- Trocar de câmera sozinho se a escolhida for desconectada, e voltar quando ela reconectar
- Tela de bloqueio em **todos** os monitores, por cima de tudo (inclusive vídeo em tela cheia), aparecendo na hora
- O olho animado: segue a pessoa, pisca, contrai a pupila de perto, fica com raiva com senha errada, respira
- Sair só com a senha do usuário (ou biometria); pausar a mídia que estiver tocando
- Temas no **mesmo formato** da versão Mac (`tema.json` + `iris.png`/`esclera.png`/`pele.png`), pra um tema funcionar nos dois

### Pontos de partida no Windows (pra analisar, não pra seguir à risca)

| Peça | Opções no Windows |
|------|-------------------|
| Câmera | `Windows.Media.Capture` (WinRT), Media Foundation, OpenCV |
| Rosto | `Windows.Media.FaceAnalysis.FaceDetector` (já vem no Windows), OpenCV DNN, MediaPipe |
| Olho animado | Win2D / Direct2D, WinUI 3 / WPF com composição, ou um motor 2D |
| Tela de bloqueio | janela sem borda `WS_EX_TOPMOST` por monitor + hook de teclado de baixo nível pra engolir Win, Alt+Tab etc. |
| Senha | `LogonUser` (senha do Windows) ou Windows Hello via `UserConsentVerifier` |
| Pausar mídia | `GlobalSystemMediaTransportControlsSessionManager` |
| Bandeja e inicialização | `NotifyIcon` / `Shell_NotifyIcon`; chave `Run` no registro ou pasta Inicializar |

Uma diferença importante pra decidir na análise: no Windows nenhum app consegue bloquear **Ctrl+Alt+Del**, que
sempre abre a tela segura do sistema. Ou seja, a tela do Eye sozinha nunca vai ser um bloqueio de verdade. Vale
pensar se o certo é o olho ser só a cara do bloqueio e chamar o bloqueio real do Windows (`LockWorkStation`) por
baixo, ou outra solução.

### Pedido pronto para uma IA (ex.: Claude Code no Windows)

> Leia este repositório inteiro, principalmente `README.md` e `Sources/`. Ele é um app de macOS. Quero uma versão
> para Windows. Não traduza arquivo por arquivo: primeiro analise o que o app faz e por quê, depois pense por
> conta própria na estrutura mais interessante para o Windows (linguagem, framework, módulos, o que pode ser
> compartilhado com a versão Mac). Escreva a proposta em `windows/PROPOSTA.md` com a estrutura, as alternativas
> que você descartou e os riscos (inclusive Ctrl+Alt+Del). Os temas precisam usar o mesmo formato da seção
> "Temas" do README. Só comece a implementar depois de eu aprovar a proposta.
