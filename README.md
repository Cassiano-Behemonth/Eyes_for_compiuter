# Eye

Vigia o computador pela webcam. Se ninguém aparece na câmera por um tempo, cobre a tela com um olho de dragão
que segue com a pupila quem passar na frente. Para sair, digite a senha do macOS e aperte Enter, ou use a digital (Touch ID).

Hoje o Eye roda **só no macOS** (14 ou mais novo). Para Windows, veja [Windows](#windows) no fim deste arquivo e o guia completo em [WINDOWS.md](WINDOWS.md).

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

## Windows (Protetor de Tela)

A versão para Windows foi adaptada com motor procedural acelerado por hardware (Canvas 2D/Direct2D) e suporte nativo ao sistema operacional.

### Como Rodar no Windows

Você tem duas formas simples de rodar:

1. **Execução Imediata (1 clique):**
   - Dê dois cliques em `iniciar.bat`
   - O olho da criatura abrirá instantaneamente em tela cheia na resolução máxima do seu monitor (Full HD, 2K, 4K).
   - *Alternativa via terminal:* `python app.py`

2. **Como Protetor de Tela Oficial do Windows (`.scr`):**
   - O arquivo `Eye.scr` já vem compilado na raiz do projeto.
   - Dê dois cliques em `instalar_protetor_de_tela.bat`, ou clique com o botão direito em `Eye.scr` e selecione **"Instalar"** ou **"Testar"**.
   - Para recompilar quando quiser: execute `compilar_scr.bat`.

---

### Comportamento Interativo e Menu de "Tema"

- **Ao mexer o mouse:**
  - O cursor aparece e a pupila da criatura segue o movimento do seu mouse suavemente pela tela.
  - Um menu flutuante elegante com a opção **"Tema / Criatura"** surge no topo da tela.
  - Clicando no menu, você pode alternar na hora a criatura exposta:
    - 🐉 **Dragão** (O clássico réptil de fogo)
    - ❄️ **Gelo** (Wyrm das neves cristalino)
    - 🐍 **Veneno** (Basilisco com sangue ácido esmeralda)
    - 🌑 **Sombra** (Entidade abissal do vazio)
    - 🌋 **Lava** (Criatura de magma incandescente)
    - ✨ **Ouro** (Dragão celestial dourado)
    - *Ou qualquer tema criado por você!*
- **Ocultamento automático:**
  - Se você parar de mexer o mouse por alguns segundos (~3,5 segundos), o menu de tema e o cursor desaparecem suavemente.
  - A tela volta ao modo imersivo e hipnótico de protetor de tela, onde a criatura continua respirando, piscando suas pálpebras amendoadas e observando os arredores.
- **Vigilância por Webcam (opcional):**
  - No menu superior, clique no ícone de câmera (📷) para que o dragão passe a rastrear você pela webcam.

---

### Como Inserir Novos Temas no Windows

Todos os temas do Windows ficam organizados na pasta:
```
Temas/
```

Para adicionar uma nova criatura:
1. Crie uma pasta dentro de `Temas/` com o nome da criatura desejada (ex: `Temas/Dragao_Esmeralda/`).
2. Crie um arquivo `tema.json` dentro dessa pasta.
3. Se quiser usar ilustrações próprias, pode colocar opcionalmente:
   - `iris.png` (textura da íris)
   - `esclera.png` (textura do fundo do olho)
   - `pele.png` (textura do fundo de pele/escamas)
4. Ao mexer o mouse no protetor de tela, sua nova criatura aparecerá automaticamente na lista de temas!
5. Veja o guia passo a passo em [Temas/README_TEMAS.md](Temas/README_TEMAS.md).
