// Shared emoji dataset for Nuru pickers (web).
// Keep category names + ordering in sync with mobile picker.

export type EmojiCategory = {
  id: string;
  label: string;
  icon: string; // single emoji used as the rail icon
  emojis: string[];
};

export const REACTION_ROW = ["❤️", "😂", "😮", "😢", "🙏", "🔥", "🎉", "👍"];

export const SKIN_TONES = ["", "🏻", "🏼", "🏽", "🏾", "🏿"];

// A small keyword map so search reaches across categories.
// Keys are emojis, values are space-separated keywords.
export const KEYWORDS: Record<string, string> = {
  "😀": "grin happy smile",
  "😂": "laugh tears joy lol",
  "🤣": "rofl rolling laugh",
  "🥰": "love smile heart",
  "😍": "heart eyes love",
  "😘": "kiss love",
  "😎": "cool sunglasses",
  "🥳": "party celebrate",
  "😭": "cry sob sad",
  "😡": "angry mad",
  "❤️": "heart love red",
  "🧡": "heart orange",
  "💛": "heart yellow",
  "💚": "heart green",
  "💙": "heart blue",
  "💜": "heart purple",
  "🖤": "heart black",
  "🤍": "heart white",
  "💔": "broken heart sad",
  "🔥": "fire lit hot",
  "🎉": "party tada celebrate",
  "🙏": "pray thanks please",
  "👍": "thumbs up like ok",
  "👎": "thumbs down dislike",
  "👏": "clap applause",
  "💪": "strong muscle",
  "🌹": "rose flower",
  "🌻": "sunflower flower",
  "☕": "coffee drink",
  "🍕": "pizza food",
  "⚽": "football soccer",
  "🏀": "basketball",
  "✈️": "plane travel",
  "🚗": "car",
  "🎵": "music note",
  "📷": "camera photo",
  "💯": "hundred perfect",
  "✨": "sparkles shine",
};

export const CATEGORIES: EmojiCategory[] = [
  {
    id: "smileys",
    label: "Smileys",
    icon: "😀",
    emojis: [
      "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊","😇","🥰","😍","🤩","😘","😗","😚","😙",
      "😋","😛","😜","🤪","😝","🤑","🤗","🤭","🤫","🤔","🤐","🤨","😐","😑","😶","😏","😒","🙄","😬","🤥",
      "😌","😔","😪","🤤","😴","😷","🤒","🤕","🤢","🤮","🤧","🥵","🥶","🥴","😵","🤯","🤠","🥳","😎","🤓",
      "🧐","😕","😟","🙁","☹️","😮","😯","😲","😳","🥺","😦","😧","😨","😰","😥","😢","😭","😱","😖","😣",
      "😞","😓","😩","😫","🥱","😤","😡","😠","🤬","😈","👿","💀","☠️","💩","🤡","👹","👺","👻","👽","👾",
    ],
  },
  {
    id: "people",
    label: "People",
    icon: "👋",
    emojis: [
      "👋","🤚","🖐️","✋","🖖","👌","🤌","🤏","✌️","🤞","🤟","🤘","🤙","👈","👉","👆","🖕","👇","☝️","👍",
      "👎","✊","👊","🤛","🤜","👏","🙌","👐","🤲","🤝","🙏","✍️","💅","🤳","💪","🦾","🦵","🦿","🦶","👂",
      "🧒","👦","👧","🧑","👨","👩","🧓","👴","👵","👮","🕵️","💂","👷","🤴","👸","👳","👲","🧕","🤵","👰",
    ],
  },
  {
    id: "nature",
    label: "Nature",
    icon: "🌿",
    emojis: [
      "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮","🐷","🐸","🐵","🐔","🐧","🐦","🐤","🐣",
      "🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞","🐜","🦟","🦗","🕷️","🐢","🐍","🦎",
      "🌵","🎄","🌲","🌳","🌴","🌱","🌿","☘️","🍀","🎍","🎋","🍃","🍂","🍁","🌾","🌺","🌻","🌹","🥀","🌷",
    ],
  },
  {
    id: "food",
    label: "Food",
    icon: "🍔",
    emojis: [
      "🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑",
      "🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🫒","🧄","🧅","🥔","🍠","🥐","🥖","🍞","🥨","🥯","🥞","🧇","🧀",
      "☕","🍵","🍶","🍾","🍷","🍸","🍹","🍺","🍻","🥂","🥃","🥤","🧋","🧃","🧉","🍽️","🥢","🥄","🍴","🧂",
    ],
  },
  {
    id: "activities",
    label: "Activities",
    icon: "⚽",
    emojis: [
      "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱","🪀","🏓","🏸","🏒","🏑","🥍","🏏","🪃","🥅","⛳",
      "🪁","🏹","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷","⛸️","🥌","🎿","⛷️","🏂","🪂","🏋️","🤼","🤸","🤺",
    ],
  },
  {
    id: "travel",
    label: "Travel",
    icon: "✈️",
    emojis: [
      "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛻","🚚","🚛","🚜","🛵","🏍️","🛺","🚲","🛴","🛹",
      "🚂","🚆","🚇","🚊","🚉","✈️","🛫","🛬","🛩️","🚁","🚟","🚠","🚡","🛰️","🚀","🛸","🛶","⛵","🚤","🛥️",
    ],
  },
  {
    id: "objects",
    label: "Objects",
    icon: "💡",
    emojis: [
      "⌚","📱","💻","⌨️","🖥️","🖨️","🖱️","🖲️","🕹️","🗜️","💾","💿","📀","📼","📷","📸","📹","🎥","📽️","🎞️",
      "📞","☎️","📟","📠","📺","📻","🎙️","🎚️","🎛️","🧭","⏱️","⏲️","⏰","🕰️","⌛","⏳","📡","🔋","🔌","💡",
    ],
  },
  {
    id: "symbols",
    label: "Symbols",
    icon: "❤️",
    emojis: [
      "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝","💟","☮️",
      "✝️","☪️","🕉️","☸️","✡️","🔯","🕎","☯️","☦️","🛐","⛎","♈","♉","♊","♋","♌","♍","♎","♏","♐",
      "💯","✨","💫","⭐","🌟","🌠","☄️","💥","🔥","🌈","☀️","🌤️","⛅","🌥️","☁️","🌦️","🌧️","⛈️","🌩️","🌨️",
    ],
  },
  {
    id: "flags",
    label: "Flags",
    icon: "🏳️",
    emojis: [
      "🏁","🚩","🎌","🏴","🏳️","🏳️‍🌈","🏳️‍⚧️","🏴‍☠️","🇺🇳","🇰🇪","🇺🇸","🇬🇧","🇫🇷","🇩🇪","🇮🇹","🇪🇸","🇨🇳","🇯🇵","🇰🇷","🇮🇳",
      "🇧🇷","🇨🇦","🇦🇺","🇿🇦","🇳🇬","🇪🇬","🇬🇭","🇪🇹","🇹🇿","🇺🇬","🇷🇼","🇳🇱","🇸🇪","🇨🇭","🇵🇹","🇲🇽","🇦🇷","🇮🇪","🇳🇿","🇸🇬",
    ],
  },
];

export function searchEmojis(query: string): string[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const cat of CATEGORIES) {
    for (const e of cat.emojis) {
      if (seen.has(e)) continue;
      const kw = (KEYWORDS[e] || "") + " " + cat.label.toLowerCase();
      if (kw.includes(q) || e.includes(q)) {
        seen.add(e);
        out.push(e);
      }
    }
  }
  return out.slice(0, 80);
}

// Persistence helpers (localStorage), shared with the mobile picker keys.
const RECENT_KEY = "emoji_recent";
const FREQ_KEY = "emoji_frequent";

export function loadRecent(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY);
    return raw ? (JSON.parse(raw) as string[]) : [];
  } catch {
    return [];
  }
}

export function loadFrequent(): Array<[string, number]> {
  try {
    const raw = localStorage.getItem(FREQ_KEY);
    return raw ? (JSON.parse(raw) as Array<[string, number]>) : [];
  } catch {
    return [];
  }
}

export function trackEmoji(emoji: string) {
  try {
    const recent = [emoji, ...loadRecent().filter((e) => e !== emoji)].slice(0, 32);
    localStorage.setItem(RECENT_KEY, JSON.stringify(recent));
    const freq = new Map(loadFrequent());
    freq.set(emoji, (freq.get(emoji) || 0) + 1);
    localStorage.setItem(FREQ_KEY, JSON.stringify(Array.from(freq.entries())));
  } catch {
    /* ignore quota errors */
  }
}

export function topFrequent(limit = 8): string[] {
  const entries = loadFrequent().sort((a, b) => b[1] - a[1]);
  const out = entries.slice(0, limit).map(([e]) => e);
  if (out.length >= limit) return out;
  const fill = REACTION_ROW.filter((e) => !out.includes(e));
  return [...out, ...fill].slice(0, limit);
}

/** Ensure color (emoji) presentation. Some codepoints like U+2764 ❤ render as
 *  a monochrome text glyph unless followed by Variation Selector-16 (U+FE0F). */
const _VS16_NEEDED = new Set([
  "\u2764","\u2665","\u2620","\u2660","\u2663","\u2666","\u263A","\u2639",
  "\u270C","\u261D","\u26A1","\u2B50","\u2728",
]);
export function normalizeEmoji(e: string | null | undefined): string {
  if (!e) return "❤️";
  return _VS16_NEEDED.has(e) ? e + "\uFE0F" : e;
}
