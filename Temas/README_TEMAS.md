# Como Criar e Inserir Novos Temas (Criaturas) no Windows

No Windows, cada criatura exposta no protetor de tela é definida por uma pasta dentro deste diretório `Temas/`.

---

## 📁 Estrutura de um Tema

Basta criar uma pasta com o nome da criatura que deseja, por exemplo:
`Temas/Dragao_Esmeralda/`

Dentro da pasta, você pode colocar:

| Arquivo | Obrigatório? | O que faz |
|---|---|---|
| `tema.json` | Recomendado | Define a paleta de cores procedural (íris, fibras, escamas, brilho, etc.) |
| `iris.png` | Opcional | Imagem personalizada da íris (quadrada, sem pupila — a pupila vertical é desenhada e se mexe por cima) |
| `esclera.png` | Opcional | Imagem de fundo do olho (atrás da íris). Proporção retangular larga (~1.8:1) |
| `pele.png` | Opcional | Imagem da pele/escamas cobrindo a tela inteira (ex: 1920x1080) |

> **Nota:** Se você não colocar imagens (`.png`), o protetor de tela desenha tudo **processualmente em alta definição (4K/60fps)** com escamas sobrepostas, veias orgânicas e milhares de fibras na íris a partir do `tema.json`!

---

## 🎨 Exemplo Completo de `tema.json`

Copie este modelo para criar a sua criatura:

```json
{
  "base": "Dragão",
  "iris": ["#ffffff", "#8affd0", "#00e699", "#009966", "#004d33", "#001a11"],
  "fibras": ["#b3ffe6", "#00e699", "#003322"],
  "esclera": ["#002b1f", "#001a13", "#000a07"],
  "veias": "#00ffaa",
  "escamas": "#0f261e",
  "brilho": "#00ffaa",
  "destaque": "#66ffcc"
}
```

### Explicação de cada campo:

1. **`base`**: Tema de partida (`"Dragão"`, `"Gelo"`, `"Veneno"`, `"Sombra"`). Qualquer campo que você não preencher virá desse tema.
2. **`iris`**: Lista com 2 a 6 cores em degradê para a íris, do centro até a borda externa.
3. **`fibras`**: 3 cores das fibras radiais da íris (clara, média e escura).
4. **`esclera`**: Degradê do fundo do olho (do centro para a borda).
5. **`veias`**: Cor das ramificações de veias de sangue que cruzam o olho.
6. **`escamas`**: Cor principal das escamas e pálpebras sob a luz. As sombras e relevos 3D são gerados automaticamente a partir desta cor.
7. **`brilho`**: Cor da aura brilhante mística pulsante ao redor do olho.
8. **`destaque`**: Cor dos pontos de destaque e acentos da criatura.

---

## 🚀 Como testar seu novo tema:

1. Ao criar a pasta dentro de `Temas/`, ela **aparece automaticamente no menu "Tema"** quando você mexer o mouse na tela.
2. Você pode clicar no menu e selecionar sua nova criatura instantaneamente!
3. Se quiser alterar as cores, edite o `tema.json` e escolha a criatura novamente para recarregar as novas cores.
