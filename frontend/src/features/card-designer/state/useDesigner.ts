/** Editor state with undo/redo. Plain useReducer to avoid extra deps. */
import { useCallback, useMemo, useReducer, useRef } from "react";
import type { CardDesignDoc, CardLayer } from "@/lib/api/invitationTemplates";

interface State {
  doc: CardDesignDoc;
  selectedId: string | null;
  past: CardDesignDoc[];
  future: CardDesignDoc[];
  dirty: boolean;
}

type Action =
  | { type: "set"; doc: CardDesignDoc }
  | { type: "patchLayer"; id: string; patch: Partial<CardLayer> }
  | { type: "addLayer"; layer: CardLayer }
  | { type: "removeLayer"; id: string }
  | { type: "duplicateLayer"; id: string }
  | { type: "reorder"; id: string; dir: "up" | "down" | "top" | "bottom" }
  | { type: "select"; id: string | null }
  | { type: "undo" }
  | { type: "redo" }
  | { type: "markClean" };

const HISTORY_CAP = 50;

function pushHistory(state: State, nextDoc: CardDesignDoc): State {
  const past = [...state.past, state.doc].slice(-HISTORY_CAP);
  return { ...state, doc: nextDoc, past, future: [], dirty: true };
}

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case "set":
      return pushHistory(state, action.doc);
    case "patchLayer": {
      const layers = state.doc.layers.map(l => (l.id === action.id ? ({ ...l, ...action.patch } as CardLayer) : l));
      return pushHistory(state, { ...state.doc, layers });
    }
    case "addLayer":
      return pushHistory(state, { ...state.doc, layers: [...state.doc.layers, action.layer] });
    case "removeLayer":
      return pushHistory(state, { ...state.doc, layers: state.doc.layers.filter(l => l.id !== action.id) });
    case "duplicateLayer": {
      const orig = state.doc.layers.find(l => l.id === action.id);
      if (!orig) return state;
      const copy = { ...orig, id: `${orig.type}_${Date.now()}`, x: orig.x + 20, y: orig.y + 20 } as CardLayer;
      return pushHistory(state, { ...state.doc, layers: [...state.doc.layers, copy] });
    }
    case "reorder": {
      const idx = state.doc.layers.findIndex(l => l.id === action.id);
      if (idx < 0) return state;
      const layers = [...state.doc.layers];
      const [item] = layers.splice(idx, 1);
      let newIdx = idx;
      if (action.dir === "up") newIdx = Math.min(layers.length, idx + 1);
      else if (action.dir === "down") newIdx = Math.max(0, idx - 1);
      else if (action.dir === "top") newIdx = layers.length;
      else newIdx = 0;
      layers.splice(newIdx, 0, item);
      return pushHistory(state, { ...state.doc, layers });
    }
    case "select":
      return { ...state, selectedId: action.id };
    case "undo": {
      if (!state.past.length) return state;
      const prev = state.past[state.past.length - 1];
      return { ...state, doc: prev, past: state.past.slice(0, -1), future: [state.doc, ...state.future], dirty: true };
    }
    case "redo": {
      if (!state.future.length) return state;
      const next = state.future[0];
      return { ...state, doc: next, past: [...state.past, state.doc], future: state.future.slice(1), dirty: true };
    }
    case "markClean":
      return { ...state, dirty: false };
  }
}

export function useDesigner(initial: CardDesignDoc) {
  const [state, dispatch] = useReducer(reducer, {
    doc: initial,
    selectedId: null,
    past: [],
    future: [],
    dirty: false,
  } as State);
  const ref = useRef(state);
  ref.current = state;
  const selected = useMemo(
    () => state.doc.layers.find(l => l.id === state.selectedId) || null,
    [state.doc.layers, state.selectedId],
  );
  const api = useMemo(() => ({
    state, selected, dispatch,
    setDoc: (doc: CardDesignDoc) => dispatch({ type: "set", doc }),
    patch: (id: string, patch: Partial<CardLayer>) => dispatch({ type: "patchLayer", id, patch }),
    add: (layer: CardLayer) => dispatch({ type: "addLayer", layer }),
    remove: (id: string) => dispatch({ type: "removeLayer", id }),
    duplicate: (id: string) => dispatch({ type: "duplicateLayer", id }),
    reorder: (id: string, dir: "up" | "down" | "top" | "bottom") => dispatch({ type: "reorder", id, dir }),
    select: (id: string | null) => dispatch({ type: "select", id }),
    undo: () => dispatch({ type: "undo" }),
    redo: () => dispatch({ type: "redo" }),
    markClean: () => dispatch({ type: "markClean" }),
  }), [state, selected]);
  return api;
}

/** Helpers to build new layers with sane defaults. */
let nid = 1;
const id = (k: string) => `${k}_${Date.now()}_${nid++}`;

export const newLayers = {
  text(text = "New text"): CardLayer {
    return {
      id: id("text"), type: "text", name: "Text", text,
      x: 80, y: 80, width: 600, height: 80, opacity: 1, visible: true, locked: false, wrap: true,
      style: { fontFamily: "Inter", fontSize: 36, fontWeight: "600", color: "#111111", textAlign: "left", lineHeight: 1.2 },
    };
  },
  dynamic(placeholder: string, label: string): CardLayer {
    return {
      ...newLayers.text(placeholder),
      name: label,
      placeholder,
    } as CardLayer;
  },
  rect(): CardLayer {
    return {
      id: id("rect"), type: "shape", shape: "rect", name: "Rectangle",
      x: 100, y: 100, width: 400, height: 200, opacity: 1, visible: true, locked: false,
      style: { fill: "#E5E7EB", cornerRadius: 12, strokeWidth: 0 },
    };
  },
  circle(): CardLayer {
    return {
      id: id("circle"), type: "shape", shape: "circle", name: "Circle",
      x: 100, y: 100, width: 200, height: 200, opacity: 1, visible: true, locked: false,
      style: { fill: "#E5E7EB", strokeWidth: 0 },
    };
  },
  line(): CardLayer {
    return {
      id: id("line"), type: "shape", shape: "line", name: "Line",
      x: 100, y: 200, width: 400, height: 4, opacity: 1, visible: true, locked: false,
      style: { stroke: "#111111", strokeWidth: 2 },
    };
  },
  image(src: string): CardLayer {
    return {
      id: id("img"), type: "image", name: "Image", src,
      x: 100, y: 100, width: 400, height: 400, opacity: 1, visible: true, locked: false,
      fit: "cover", borderRadius: 0,
    };
  },
  qr(): CardLayer {
    return {
      id: id("qr"), type: "qr", name: "QR Code", placeholder: "{{qr_code}}",
      x: 100, y: 100, width: 240, height: 240, opacity: 1, visible: true, locked: false,
      style: { foregroundColor: "#000000", backgroundColor: "#FFFFFF", padding: 12, borderRadius: 12 },
    };
  },
};

export function blankDoc(width = 1080, height = 1350): CardDesignDoc {
  return { version: 1, platform: "web", canvas: { width, height, backgroundColor: "#FFFFFF" }, layers: [] };
}

export function smartStarterDoc(): CardDesignDoc {
  return {
    version: 1,
    platform: "web",
    canvas: { width: 1080, height: 1350, backgroundColor: "#FFFFFF" },
    layers: [
      { ...newLayers.dynamic("{{event_title}}", "Event Title"), x: 80, y: 140, width: 920, height: 120,
        style: { fontFamily: "Playfair Display, serif", fontSize: 72, fontWeight: "700", color: "#111", textAlign: "center", lineHeight: 1.1 } } as CardLayer,
      { ...newLayers.dynamic("{{guest_name}}", "Guest Name"), x: 80, y: 320, width: 920, height: 90,
        style: { fontFamily: "Inter", fontSize: 44, fontWeight: "600", color: "#111", textAlign: "center", lineHeight: 1.2 } } as CardLayer,
      { ...newLayers.dynamic("{{event_date}} - {{event_time}}", "Date/Time"), x: 80, y: 440, width: 920, height: 60,
        style: { fontFamily: "Inter", fontSize: 28, fontWeight: "400", color: "#444", textAlign: "center", lineHeight: 1.2 } } as CardLayer,
      { ...newLayers.dynamic("{{event_location}}", "Location"), x: 80, y: 510, width: 920, height: 60,
        style: { fontFamily: "Inter", fontSize: 26, fontWeight: "400", color: "#666", textAlign: "center", lineHeight: 1.2 } } as CardLayer,
      { ...newLayers.qr(), x: 420, y: 880, width: 240, height: 240 },
      { ...newLayers.dynamic("Invite #{{invite_code}}", "Invite Code"), x: 80, y: 1180, width: 920, height: 50,
        style: { fontFamily: "Inter", fontSize: 22, fontWeight: "400", color: "#888", textAlign: "center", lineHeight: 1.2 } } as CardLayer,
    ],
  };
}
