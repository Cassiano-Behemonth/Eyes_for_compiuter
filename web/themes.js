/**
 * Temas do Eye - Cores e definições das criaturas
 */

function hexToRgb(hex) {
  let clean = hex.replace('#', '').trim();
  if (clean.length === 3) {
    clean = clean.split('').map(c => c + c).join('');
  }
  const num = parseInt(clean, 16);
  return {
    r: (num >> 16) & 0xff,
    g: (num >> 8) & 0xff,
    b: num & 0xff
  };
}

function rgbToHex(r, g, b) {
  const clamp = v => Math.min(255, Math.max(0, Math.round(v)));
  return '#' + [clamp(r), clamp(g), clamp(b)].map(x => x.toString(16).padStart(2, '0')).join('');
}

function shadeColor(hex, k, alpha = 1) {
  const { r, g, b } = hexToRgb(hex);
  const nr = Math.min(255, Math.max(0, Math.round(r * k)));
  const ng = Math.min(255, Math.max(0, Math.round(g * k)));
  const nb = Math.min(255, Math.max(0, Math.round(b * k)));
  return alpha === 1 ? `rgb(${nr}, ${ng}, ${nb})` : `rgba(${nr}, ${ng}, ${nb}, ${alpha})`;
}

function colorWithAlpha(hex, alpha) {
  const { r, g, b } = hexToRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

const BUILTIN_THEMES = {
  "Dragão": {
    name: "Dragão",
    description: "Réptil ancestral de fogo com escamas escarlates e olhar ardente.",
    icon: "🐉",
    base: "Dragão",
    iris: ["#fff1a8", "#ffc23a", "#ff7a0a", "#e02a00", "#8a0700", "#2a0000"],
    fibras: ["#ffd25a", "#ff4a00", "#3a0000"],
    esclera: ["#6e1402", "#3a0500", "#120100"],
    veias: "#2a0000",
    escamas: "#611a0c",
    brilho: "#ff3a00",
    destaque: "#ff5a2a"
  },
  "Gelo": {
    name: "Gelo",
    description: "Wyrm glacial dos picos congelados com pupila cristalina e escamas azuis.",
    icon: "❄️",
    base: "Gelo",
    iris: ["#f4ffff", "#b8f0ff", "#5ac8ff", "#1a78e0", "#0a2f8a", "#020a2a"],
    fibras: ["#d8f8ff", "#3aa0ff", "#001030"],
    esclera: ["#0e3a6e", "#06203a", "#010612"],
    veias: "#000a2a",
    escamas: "#1a3f61",
    brilho: "#3aa8ff",
    destaque: "#6ac8ff"
  },
  "Veneno": {
    name: "Veneno",
    description: "Basilisco das sombras com olhar hipnótico e sangue corrosivo esmeralda.",
    icon: "🐍",
    base: "Veneno",
    iris: ["#f6ffb0", "#c8ff3a", "#6ee00a", "#1a9a00", "#0a4a05", "#021a00"],
    fibras: ["#e0ff6a", "#4ac000", "#0a2a00"],
    esclera: ["#2a5a06", "#143a02", "#041200"],
    veias: "#0a2000",
    escamas: "#1f4a12",
    brilho: "#6aff1a",
    destaque: "#9aff4a"
  },
  "Sombra": {
    name: "Sombra",
    description: "Entidade abissal do vazio cósmico com íris violeta espectral.",
    icon: "🌑",
    base: "Sombra",
    iris: ["#ffe0ff", "#e0a0ff", "#b050ff", "#7a10e0", "#3a0680", "#12002a"],
    fibras: ["#f0c0ff", "#a040ff", "#1a0030"],
    esclera: ["#3a0a5e", "#1e0436", "#0a0112"],
    veias: "#140024",
    escamas: "#3a1a61",
    brilho: "#b040ff",
    destaque: "#c070ff"
  },
  "Lava": {
    name: "Lava",
    description: "Titã do magma com coração vulcânico e veias incandescentes.",
    icon: "🌋",
    base: "Dragão",
    iris: ["#ffffff", "#fff27a", "#ffb000", "#ff5a00", "#a01000", "#300000"],
    fibras: ["#fff6b0", "#ff8a00", "#400800"],
    esclera: ["#ff6a00", "#7a1400", "#1a0200"],
    veias: "#ffb030",
    escamas: "#3a3030",
    brilho: "#ff7a00",
    destaque: "#ffb04a"
  },
  "Ouro": {
    name: "Ouro",
    description: "Dragão celestial com escamas de ouro polido e olhar divino solar.",
    icon: "✨",
    base: "Dragão",
    iris: ["#ffffff", "#fffbb0", "#ffd700", "#d4af37", "#aa7a1e", "#3a2500"],
    fibras: ["#ffffff", "#ffe066", "#664400"],
    esclera: ["#4a3800", "#241c00", "#0d0a00"],
    veias: "#ffd700",
    escamas: "#2b220c",
    brilho: "#ffe066",
    destaque: "#ffd700"
  }
};

window.ThemeManager = {
  current: BUILTIN_THEMES["Dragão"],
  allThemes: { ...BUILTIN_THEMES },

  async loadThemes() {
    const serverUrl = window.SERVER_URL !== undefined ? window.SERVER_URL : (window.location.protocol.startsWith('http') ? '' : 'http://127.0.0.1:54321');
    try {
      const resp = await fetch(serverUrl + '/api/temas');
      if (resp.ok) {
        const serverThemes = await resp.json();
        for (const [key, theme] of Object.entries(serverThemes)) {
          this.allThemes[key] = {
            ...this.normalizeTheme(theme),
            name: key
          };
        }
      }
    } catch (e) {
      // Servidor local não conectado ou modo estático; carrega do localStorage se houver
    }

    try {
      const savedCustom = localStorage.getItem('eye_custom_themes');
      if (savedCustom) {
        const parsed = JSON.parse(savedCustom);
        Object.assign(this.allThemes, parsed);
      }
    } catch (_) {}

    // Recupera o tema salvo
    const savedName = localStorage.getItem('eye_selected_theme');
    if (savedName && this.allThemes[savedName]) {
      this.current = this.allThemes[savedName];
    }
    return this.allThemes;
  },

  normalizeTheme(raw) {
    const base = BUILTIN_THEMES[raw.base] || BUILTIN_THEMES["Dragão"];
    return {
      name: raw.name || base.name,
      base: raw.base || "Dragão",
      description: raw.description || `Criatura baseada em ${raw.base || "Dragão"}`,
      icon: raw.icon || "👁️",
      iris: Array.isArray(raw.iris) && raw.iris.length >= 2 ? raw.iris : base.iris,
      fibras: Array.isArray(raw.fibras) && raw.fibras.length >= 3 ? raw.fibras.slice(0, 3) : base.fibras,
      esclera: Array.isArray(raw.esclera) && raw.esclera.length >= 2 ? raw.esclera : base.esclera,
      veias: raw.veias || base.veias,
      escamas: raw.escamas || base.escamas,
      brilho: raw.brilho || base.brilho,
      destaque: raw.destaque || base.destaque,
      irisImage: raw.irisImage || null,
      scleraImage: raw.scleraImage || null,
      skinImage: raw.skinImage || null
    };
  },

  selectTheme(name) {
    if (this.allThemes[name]) {
      this.current = this.allThemes[name];
      try {
        localStorage.setItem('eye_selected_theme', name);
      } catch (_) {}
      return this.current;
    }
    return null;
  }
};
