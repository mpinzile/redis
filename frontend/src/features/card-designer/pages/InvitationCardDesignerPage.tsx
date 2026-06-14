import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { Stage, Layer, Rect, Transformer, Text, Image as KImage, Circle, Line, Group } from "react-konva";
import useImage from "use-image";
import type Konva from "konva";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ScrollArea } from "@/components/ui/scroll-area";
import { toast } from "sonner";
import {
  ArrowLeft, Undo2, Redo2, Save, Eye, Star, Type, Square, Circle as CircleIcon,
  Minus, ImageIcon, QrCode, Trash2, Copy, Lock, Unlock, EyeOff, Eye as EyeOn,
  ChevronUp, ChevronDown,
} from "lucide-react";
import { invitationTemplatesApi, type CardDesignDoc, type CardLayer } from "@/lib/api/invitationTemplates";
import { blankDoc, newLayers, smartStarterDoc, useDesigner } from "../state/useDesigner";
import { applyPlaceholders, SAMPLE_CONTEXT } from "../render/placeholders";
import { qrDataUrl } from "../render/qr";

const PRESETS = [
  { id: "portrait", label: "Portrait", w: 1080, h: 1350 },
  { id: "square", label: "Square", w: 1080, h: 1080 },
  { id: "story", label: "Story", w: 1080, h: 1920 },
];

const DYNAMIC_FIELDS: { key: string; label: string }[] = [
  { key: "{{guest_name}}", label: "Guest Name" },
  { key: "{{event_title}}", label: "Event Title" },
  { key: "{{event_date}}", label: "Event Date" },
  { key: "{{event_time}}", label: "Event Time" },
  { key: "{{event_location}}", label: "Event Location" },
  { key: "{{organizer_name}}", label: "Organizer" },
  { key: "{{invite_code}}", label: "Invite Code" },
];

// ───── Konva node helpers ─────
function Img({ src, width, height, fit }: { src: string; width: number; height: number; fit?: string }) {
  const [img] = useImage(src, "anonymous");
  if (!img) return null;
  let w = width, h = height, x = 0, y = 0;
  const r = img.width / img.height;
  if (fit === "contain") {
    if (r > width / height) { h = width / r; y = (height - h) / 2; } else { w = height * r; x = (width - w) / 2; }
  } else if (fit === "cover" || !fit) {
    if (r > width / height) { w = height * r; x = (width - w) / 2; } else { h = width / r; y = (height - h) / 2; }
  }
  return <KImage image={img} x={x} y={y} width={w} height={h} />;
}

function QrNode({ payload, w, h, fg, bg, padding }: { payload: string; w: number; h: number; fg: string; bg: string; padding: number }) {
  const [src, setSrc] = useState("");
  const size = Math.min(w, h) - padding * 2;
  useEffect(() => {
    let alive = true;
    qrDataUrl(payload, size, fg, bg).then(u => { if (alive) setSrc(u); });
    return () => { alive = false; };
  }, [payload, size, fg, bg]);
  const [img] = useImage(src);
  if (!img) return <Rect width={size} height={size} fill={bg} />;
  return <KImage image={img} width={size} height={size} />;
}

// ───── Page ─────
export default function InvitationCardDesignerPage() {
  const { eventId, templateId } = useParams<{ eventId: string; templateId: string }>();
  const [params] = useSearchParams();
  const startMode = params.get("start") || "smart"; // smart|blank|template
  const navigate = useNavigate();

  const [name, setName] = useState("Untitled design");
  const [savedId, setSavedId] = useState<string | null>(templateId || null);
  const [loaded, setLoaded] = useState(false);
  const stageRef = useRef<Konva.Stage | null>(null);
  const trRef = useRef<Konva.Transformer | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [stageScale, setStageScale] = useState(0.5);

  const initial = useMemo<CardDesignDoc>(() => (startMode === "blank" ? blankDoc() : smartStarterDoc()), [startMode]);
  const ed = useDesigner(initial);
  const { state, selected } = ed;
  const doc = state.doc;

  // Load existing template
  useEffect(() => {
    if (!templateId || !eventId) { setLoaded(true); return; }
    invitationTemplatesApi.list(eventId).then(res => {
      const t = res.data?.find(x => x.id === templateId);
      if (t) {
        setName(t.name);
        ed.setDoc(t.design_json);
        ed.markClean();
      }
    }).finally(() => setLoaded(true));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [templateId, eventId]);

  // Fit canvas to container
  useEffect(() => {
    const fit = () => {
      const el = containerRef.current; if (!el) return;
      const padding = 60;
      const sx = (el.clientWidth - padding) / doc.canvas.width;
      const sy = (el.clientHeight - padding) / doc.canvas.height;
      setStageScale(Math.max(0.1, Math.min(sx, sy)));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, [doc.canvas.width, doc.canvas.height]);

  // Transformer attachment
  useEffect(() => {
    if (!trRef.current || !stageRef.current) return;
    const node = state.selectedId ? stageRef.current.findOne(`#${state.selectedId}`) : null;
    if (node) {
      trRef.current.nodes([node]);
    } else {
      trRef.current.nodes([]);
    }
    trRef.current.getLayer()?.batchDraw();
  }, [state.selectedId, state.doc]);

  // Keyboard shortcuts
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      const meta = e.metaKey || e.ctrlKey;
      if (meta && e.key.toLowerCase() === "z" && !e.shiftKey) { e.preventDefault(); ed.undo(); }
      else if (meta && (e.key.toLowerCase() === "y" || (e.key.toLowerCase() === "z" && e.shiftKey))) { e.preventDefault(); ed.redo(); }
      else if (meta && e.key.toLowerCase() === "d" && state.selectedId) { e.preventDefault(); ed.duplicate(state.selectedId); }
      else if (meta && e.key.toLowerCase() === "s") { e.preventDefault(); save(false); }
      else if ((e.key === "Delete" || e.key === "Backspace") && state.selectedId) { ed.remove(state.selectedId); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.selectedId]);

  // Unsaved warn
  useEffect(() => {
    const before = (e: BeforeUnloadEvent) => { if (state.dirty) { e.preventDefault(); e.returnValue = ""; } };
    window.addEventListener("beforeunload", before);
    return () => window.removeEventListener("beforeunload", before);
  }, [state.dirty]);

  function setCanvas(w: number, h: number) {
    ed.setDoc({ ...doc, canvas: { ...doc.canvas, width: w, height: h } });
  }

  function uploadImage(file: File) {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = String(reader.result);
      ed.add(newLayers.image(dataUrl));
    };
    reader.readAsDataURL(file);
  }

  function validate(forActivate: boolean): string[] {
    const issues: string[] = [];
    const qrs = doc.layers.filter(l => l.type === "qr");
    if (forActivate && qrs.length === 0) issues.push("Add a QR Code layer before activating.");
    qrs.forEach(q => { if (Math.min(q.width, q.height) < 120) issues.push("QR is below 120px · may not scan reliably."); });
    const hasGuest = doc.layers.some(l => l.type === "text" && /\{\{\s*guest_name\s*\}\}/.test((l as any).text || (l as any).placeholder || ""));
    if (forActivate && !hasGuest) issues.push("No {{guest_name}} field · guests will see identical cards.");
    return issues;
  }

  async function generatePreviewDataUrl(): Promise<string | undefined> {
    return stageRef.current?.toDataURL({ pixelRatio: 0.4, mimeType: "image/png" });
  }

  async function save(activate: boolean) {
    if (!eventId) return;
    const issues = validate(activate);
    issues.forEach(m => toast.warning(m));
    if (activate && issues.some(i => i.startsWith("Add"))) return;
    try {
      const previewUrl = await generatePreviewDataUrl();
      let id = savedId;
      if (id) {
        await invitationTemplatesApi.update(eventId, id, {
          name, design_json: doc, canvas_width: doc.canvas.width, canvas_height: doc.canvas.height,
          preview_image_url: previewUrl,
        });
      } else {
        const res = await invitationTemplatesApi.create(eventId, {
          name, design_json: doc, canvas_width: doc.canvas.width, canvas_height: doc.canvas.height,
          preview_image_url: previewUrl,
        });
        id = res.data?.id || null;
        if (id) setSavedId(id);
      }
      if (activate && id) {
        await invitationTemplatesApi.activate(eventId, id);
        toast.success("Design activated for guests");
      } else {
        toast.success("Design saved");
      }
      ed.markClean();
    } catch (e: any) {
      toast.error(e?.message || "Could not save");
    }
  }

  // Autosave (debounced 5s when dirty)
  useEffect(() => {
    if (!state.dirty || !loaded) return;
    const t = setTimeout(() => save(false), 5000);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.dirty, doc, loaded]);

  // ───── Render ─────
  return (
    <div className="fixed inset-0 bg-muted/30 flex flex-col">
      {/* Top bar */}
      <div className="h-14 px-3 flex items-center gap-2 border-b bg-background">
        <Button variant="ghost" size="icon" onClick={() => navigate(`/events/${eventId}/invitations/cards`)}>
          <ArrowLeft className="w-4 h-4" />
        </Button>
        <Input value={name} onChange={e => setName(e.target.value)} className="w-64 h-9" autoComplete="off" />
        <Button variant="ghost" size="icon" onClick={ed.undo} disabled={!state.past.length}><Undo2 className="w-4 h-4" /></Button>
        <Button variant="ghost" size="icon" onClick={ed.redo} disabled={!state.future.length}><Redo2 className="w-4 h-4" /></Button>
        <div className="flex-1" />
        <span className="text-xs text-muted-foreground mr-2">{state.dirty ? "Unsaved" : "Saved"}</span>
        <Button variant="outline" size="sm" onClick={() => navigate(`/events/${eventId}/invitations/cards/${savedId || "new"}/preview`)} disabled={!savedId}>
          <Eye className="w-4 h-4 mr-1" /> Preview
        </Button>
        <Button variant="outline" size="sm" onClick={() => save(false)}><Save className="w-4 h-4 mr-1" /> Save</Button>
        <Button size="sm" onClick={() => save(true)}><Star className="w-4 h-4 mr-1" /> Activate</Button>
      </div>

      <div className="flex-1 flex min-h-0">
        {/* Left sidebar */}
        <div className="w-64 border-r bg-background flex flex-col">
          <Tabs defaultValue="elements" className="flex-1 flex flex-col">
            <TabsList className="grid grid-cols-4 m-2">
              <TabsTrigger value="elements">Add</TabsTrigger>
              <TabsTrigger value="dynamic">Fields</TabsTrigger>
              <TabsTrigger value="canvas">Size</TabsTrigger>
              <TabsTrigger value="layers">Layers</TabsTrigger>
            </TabsList>
            <TabsContent value="elements" className="flex-1 overflow-auto px-3 space-y-2">
              <Button variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.text("Heading"))}><Type className="w-4 h-4 mr-2" /> Heading</Button>
              <Button variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.text("Body text"))}><Type className="w-4 h-4 mr-2" /> Body</Button>
              <Button variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.rect())}><Square className="w-4 h-4 mr-2" /> Rectangle</Button>
              <Button variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.circle())}><CircleIcon className="w-4 h-4 mr-2" /> Circle</Button>
              <Button variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.line())}><Minus className="w-4 h-4 mr-2" /> Line</Button>
              <Button variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.qr())}><QrCode className="w-4 h-4 mr-2" /> QR Code</Button>
              <label className="block">
                <input type="file" accept="image/*" hidden onChange={e => { const f = e.target.files?.[0]; if (f) uploadImage(f); e.currentTarget.value = ""; }} />
                <span className="block">
                  <Button variant="outline" className="w-full justify-start" asChild>
                    <span><ImageIcon className="w-4 h-4 mr-2" /> Upload image</span>
                  </Button>
                </span>
              </label>
            </TabsContent>
            <TabsContent value="dynamic" className="flex-1 overflow-auto px-3 space-y-2">
              <p className="text-[11px] text-muted-foreground">These auto-fill per guest at download time.</p>
              {DYNAMIC_FIELDS.map(f => (
                <Button key={f.key} variant="outline" className="w-full justify-start" onClick={() => ed.add(newLayers.dynamic(f.key, f.label))}>
                  {f.label}
                </Button>
              ))}
            </TabsContent>
            <TabsContent value="canvas" className="flex-1 overflow-auto px-3 space-y-3">
              <div className="space-y-2">
                {PRESETS.map(p => (
                  <Button key={p.id} variant={doc.canvas.width === p.w && doc.canvas.height === p.h ? "default" : "outline"} className="w-full justify-start" onClick={() => setCanvas(p.w, p.h)}>
                    {p.label} <span className="ml-auto text-xs opacity-70">{p.w}×{p.h}</span>
                  </Button>
                ))}
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Background color</Label>
                <Input type="color" value={doc.canvas.backgroundColor || "#FFFFFF"} onChange={e => ed.setDoc({ ...doc, canvas: { ...doc.canvas, backgroundColor: e.target.value } })} className="h-9 p-1" />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Background image</Label>
                <input type="file" accept="image/*" onChange={e => {
                  const f = e.target.files?.[0]; if (!f) return;
                  const r = new FileReader(); r.onload = () => ed.setDoc({ ...doc, canvas: { ...doc.canvas, backgroundImageUrl: String(r.result) } });
                  r.readAsDataURL(f);
                }} className="text-xs" />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div><Label className="text-xs">Width</Label><Input type="number" value={doc.canvas.width} onChange={e => setCanvas(parseInt(e.target.value || "0"), doc.canvas.height)} className="h-9" /></div>
                <div><Label className="text-xs">Height</Label><Input type="number" value={doc.canvas.height} onChange={e => setCanvas(doc.canvas.width, parseInt(e.target.value || "0"))} className="h-9" /></div>
              </div>
            </TabsContent>
            <TabsContent value="layers" className="flex-1 overflow-hidden">
              <ScrollArea className="h-full px-2">
                <div className="space-y-1 pb-4">
                  {[...doc.layers].reverse().map((l) => (
                    <div key={l.id} className={`flex items-center gap-1 px-2 py-1.5 rounded text-xs cursor-pointer ${state.selectedId === l.id ? "bg-accent" : "hover:bg-muted"}`} onClick={() => ed.select(l.id)}>
                      <span className="flex-1 truncate">{l.name}</span>
                      <button onClick={e => { e.stopPropagation(); ed.patch(l.id, { visible: !(l.visible !== false) }); }}>{l.visible !== false ? <EyeOn className="w-3 h-3" /> : <EyeOff className="w-3 h-3" />}</button>
                      <button onClick={e => { e.stopPropagation(); ed.patch(l.id, { locked: !l.locked }); }}>{l.locked ? <Lock className="w-3 h-3" /> : <Unlock className="w-3 h-3" />}</button>
                    </div>
                  ))}
                  {doc.layers.length === 0 && <p className="text-[11px] text-muted-foreground text-center py-6">No layers yet</p>}
                </div>
              </ScrollArea>
            </TabsContent>
          </Tabs>
        </div>

        {/* Canvas */}
        <div ref={containerRef} className="flex-1 overflow-auto flex items-center justify-center p-6 bg-[radial-gradient(circle_at_center,rgba(0,0,0,0.04)_1px,transparent_1px)] bg-[length:16px_16px]">
          <div style={{ width: doc.canvas.width * stageScale, height: doc.canvas.height * stageScale, boxShadow: "0 24px 60px -20px rgba(0,0,0,0.25)" }}>
            <Stage
              ref={stageRef}
              width={doc.canvas.width * stageScale}
              height={doc.canvas.height * stageScale}
              scale={{ x: stageScale, y: stageScale }}
              onMouseDown={e => { if (e.target === e.target.getStage()) ed.select(null); }}
            >
              <Layer listening={false}>
                <Rect width={doc.canvas.width} height={doc.canvas.height} fill={doc.canvas.backgroundColor || "#fff"} />
                {doc.canvas.backgroundImageUrl && <Img src={doc.canvas.backgroundImageUrl} width={doc.canvas.width} height={doc.canvas.height} fit="cover" />}
                {/* Safe area */}
                <Rect x={40} y={40} width={doc.canvas.width - 80} height={doc.canvas.height - 80} stroke="rgba(99,102,241,0.25)" dash={[10, 8]} strokeWidth={2} />
              </Layer>
              <Layer>
                {doc.layers.filter(l => l.visible !== false).map(l => {
                  const dragHandlers = {
                    draggable: !l.locked,
                    onClick: () => ed.select(l.id),
                    onTap: () => ed.select(l.id),
                    onDragEnd: (e: any) => ed.patch(l.id, { x: Math.round(e.target.x()), y: Math.round(e.target.y()) }),
                    onTransformEnd: (e: any) => {
                      const node = e.target as Konva.Node;
                      const sx = node.scaleX(), sy = node.scaleY();
                      node.scaleX(1); node.scaleY(1);
                      ed.patch(l.id, {
                        x: Math.round(node.x()), y: Math.round(node.y()),
                        width: Math.max(20, Math.round(l.width * sx)),
                        height: Math.max(20, Math.round(l.height * sy)),
                        rotation: Math.round(node.rotation()),
                      });
                    },
                  };
                  if (l.type === "text") {
                    const resolved = applyPlaceholders((l as any).text || (l as any).placeholder || "", { ...SAMPLE_CONTEXT, qr_code: SAMPLE_CONTEXT.invite_code });
                    return (
                      <Text
                        key={l.id} id={l.id} {...dragHandlers}
                        x={l.x} y={l.y} width={l.width} height={l.height}
                        text={resolved}
                        fontFamily={l.style.fontFamily || "Inter"}
                        fontSize={l.style.fontSize || 32}
                        fontStyle={`${l.style.fontStyle || "normal"} ${l.style.fontWeight || 400}`.trim()}
                        fill={l.style.color || "#111"}
                        align={l.style.textAlign || "left"}
                        lineHeight={l.style.lineHeight || 1.2}
                        letterSpacing={l.style.letterSpacing || 0}
                        opacity={l.opacity ?? 1}
                        rotation={l.rotation ?? 0}
                        wrap={l.wrap === false ? "none" : "word"}
                        ellipsis={l.wrap === false}
                      />
                    );
                  }
                  if (l.type === "shape") {
                    if (l.shape === "circle") {
                      const r = Math.min(l.width, l.height) / 2;
                      return <Circle key={l.id} id={l.id} {...dragHandlers} x={l.x + r} y={l.y + r} radius={r} fill={l.style.fill} stroke={l.style.stroke} strokeWidth={l.style.strokeWidth || 0} opacity={l.opacity ?? 1} rotation={l.rotation ?? 0} />;
                    }
                    if (l.shape === "line") {
                      return <Line key={l.id} id={l.id} {...dragHandlers} x={l.x} y={l.y} points={[0, l.height / 2, l.width, l.height / 2]} stroke={l.style.stroke || "#000"} strokeWidth={l.style.strokeWidth || 2} opacity={l.opacity ?? 1} rotation={l.rotation ?? 0} />;
                    }
                    return <Rect key={l.id} id={l.id} {...dragHandlers} x={l.x} y={l.y} width={l.width} height={l.height} fill={l.style.fill} stroke={l.style.stroke} strokeWidth={l.style.strokeWidth || 0} cornerRadius={l.style.cornerRadius || 0} opacity={l.opacity ?? 1} rotation={l.rotation ?? 0} />;
                  }
                  if (l.type === "image" && l.src) {
                    return (
                      <Group key={l.id} id={l.id} {...dragHandlers} x={l.x} y={l.y} opacity={l.opacity ?? 1} rotation={l.rotation ?? 0}>
                        <Img src={l.src} width={l.width} height={l.height} fit={l.fit || "cover"} />
                      </Group>
                    );
                  }
                  if (l.type === "qr") {
                    const pad = l.style.padding || 0;
                    const size = Math.min(l.width, l.height);
                    return (
                      <Group key={l.id} id={l.id} {...dragHandlers} x={l.x} y={l.y} opacity={l.opacity ?? 1} rotation={l.rotation ?? 0}>
                        <Rect width={l.width} height={l.height} fill={l.style.backgroundColor || "#fff"} cornerRadius={l.style.borderRadius || 0} />
                        <Group x={(l.width - size) / 2 + pad} y={(l.height - size) / 2 + pad}>
                          <QrNode payload={SAMPLE_CONTEXT.invite_code} w={size} h={size} fg={l.style.foregroundColor || "#000"} bg={l.style.backgroundColor || "#fff"} padding={pad} />
                        </Group>
                      </Group>
                    );
                  }
                  return null;
                })}
                <Transformer ref={trRef} rotateEnabled={true} keepRatio={false} anchorSize={8} borderStroke="hsl(var(--primary))" anchorStroke="hsl(var(--primary))" />
              </Layer>
            </Stage>
          </div>
        </div>

        {/* Right sidebar */}
        <div className="w-72 border-l bg-background overflow-auto">
          {!selected && <p className="text-xs text-muted-foreground p-4">Select a layer to edit its properties.</p>}
          {selected && <PropertiesPanel layer={selected} ed={ed} />}
        </div>
      </div>
    </div>
  );
}

function PropertiesPanel({ layer, ed }: { layer: CardLayer; ed: ReturnType<typeof useDesigner> }) {
  const patch = (p: Partial<CardLayer>) => ed.patch(layer.id, p);
  return (
    <div className="p-3 space-y-3">
      <div className="flex items-center gap-1">
        <Input value={layer.name} onChange={e => patch({ name: e.target.value })} className="h-8 text-xs" autoComplete="off" />
        <Button size="icon" variant="ghost" onClick={() => ed.duplicate(layer.id)}><Copy className="w-4 h-4" /></Button>
        <Button size="icon" variant="ghost" onClick={() => ed.remove(layer.id)}><Trash2 className="w-4 h-4" /></Button>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div><Label className="text-[11px]">X</Label><Input type="number" value={layer.x} onChange={e => patch({ x: parseInt(e.target.value || "0") })} className="h-8" /></div>
        <div><Label className="text-[11px]">Y</Label><Input type="number" value={layer.y} onChange={e => patch({ y: parseInt(e.target.value || "0") })} className="h-8" /></div>
        <div><Label className="text-[11px]">W</Label><Input type="number" value={layer.width} onChange={e => patch({ width: parseInt(e.target.value || "0") })} className="h-8" /></div>
        <div><Label className="text-[11px]">H</Label><Input type="number" value={layer.height} onChange={e => patch({ height: parseInt(e.target.value || "0") })} className="h-8" /></div>
      </div>
      <div>
        <Label className="text-[11px]">Rotation</Label>
        <Slider value={[layer.rotation || 0]} min={-180} max={180} step={1} onValueChange={v => patch({ rotation: v[0] })} />
      </div>
      <div>
        <Label className="text-[11px]">Opacity</Label>
        <Slider value={[Math.round((layer.opacity ?? 1) * 100)]} min={0} max={100} step={1} onValueChange={v => patch({ opacity: v[0] / 100 })} />
      </div>
      <div className="flex gap-1">
        <Button size="sm" variant="outline" className="flex-1" onClick={() => ed.reorder(layer.id, "up")}><ChevronUp className="w-4 h-4" /></Button>
        <Button size="sm" variant="outline" className="flex-1" onClick={() => ed.reorder(layer.id, "down")}><ChevronDown className="w-4 h-4" /></Button>
      </div>

      {layer.type === "text" && (
        <div className="space-y-2 pt-2 border-t">
          <Label className="text-[11px]">Text (use {`{{guest_name}}`} etc.)</Label>
          <textarea value={(layer as any).text || ""} onChange={e => patch({ text: e.target.value } as any)} rows={3} className="w-full text-xs rounded border p-2" />
          <div className="grid grid-cols-2 gap-2">
            <div><Label className="text-[11px]">Font size</Label><Input type="number" value={layer.style.fontSize || 32} onChange={e => patch({ style: { ...layer.style, fontSize: parseInt(e.target.value || "0") } } as any)} className="h-8" /></div>
            <div><Label className="text-[11px]">Color</Label><Input type="color" value={layer.style.color || "#111"} onChange={e => patch({ style: { ...layer.style, color: e.target.value } } as any)} className="h-8 p-1" /></div>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div><Label className="text-[11px]">Font family</Label>
              <select value={layer.style.fontFamily || "Inter"} onChange={e => patch({ style: { ...layer.style, fontFamily: e.target.value } } as any)} className="h-8 w-full text-xs rounded border px-2">
                <option>Inter</option><option>Playfair Display, serif</option><option>Montserrat</option><option>Georgia, serif</option><option>Arial</option>
              </select>
            </div>
            <div><Label className="text-[11px]">Weight</Label>
              <select value={String(layer.style.fontWeight || 400)} onChange={e => patch({ style: { ...layer.style, fontWeight: e.target.value } } as any)} className="h-8 w-full text-xs rounded border px-2">
                <option value="300">Light</option><option value="400">Regular</option><option value="600">SemiBold</option><option value="700">Bold</option><option value="800">ExtraBold</option>
              </select>
            </div>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {(["left", "center", "right"] as const).map(a => (
              <Button key={a} size="sm" variant={layer.style.textAlign === a ? "default" : "outline"} onClick={() => patch({ style: { ...layer.style, textAlign: a } } as any)}>{a}</Button>
            ))}
          </div>
          <div>
            <Label className="text-[11px]">Line height {layer.style.lineHeight || 1.2}</Label>
            <Slider value={[Math.round((layer.style.lineHeight || 1.2) * 10)]} min={8} max={30} step={1} onValueChange={v => patch({ style: { ...layer.style, lineHeight: v[0] / 10 } } as any)} />
          </div>
          <label className="flex items-center gap-2 text-xs"><input type="checkbox" checked={(layer as any).wrap !== false} onChange={e => patch({ wrap: e.target.checked } as any)} /> Wrap long text</label>
        </div>
      )}

      {layer.type === "shape" && (
        <div className="space-y-2 pt-2 border-t">
          <div><Label className="text-[11px]">Fill</Label><Input type="color" value={layer.style.fill || "#000"} onChange={e => patch({ style: { ...layer.style, fill: e.target.value } } as any)} className="h-8 p-1" /></div>
          <div><Label className="text-[11px]">Stroke</Label><Input type="color" value={layer.style.stroke || "#000"} onChange={e => patch({ style: { ...layer.style, stroke: e.target.value } } as any)} className="h-8 p-1" /></div>
          <div><Label className="text-[11px]">Stroke width</Label><Input type="number" value={layer.style.strokeWidth || 0} onChange={e => patch({ style: { ...layer.style, strokeWidth: parseInt(e.target.value || "0") } } as any)} className="h-8" /></div>
          {layer.shape === "rect" && <div><Label className="text-[11px]">Corner radius</Label><Input type="number" value={layer.style.cornerRadius || 0} onChange={e => patch({ style: { ...layer.style, cornerRadius: parseInt(e.target.value || "0") } } as any)} className="h-8" /></div>}
        </div>
      )}

      {layer.type === "image" && (
        <div className="space-y-2 pt-2 border-t">
          <Label className="text-[11px]">Replace image</Label>
          <input type="file" accept="image/*" onChange={e => {
            const f = e.target.files?.[0]; if (!f) return;
            const r = new FileReader(); r.onload = () => patch({ src: String(r.result) } as any);
            r.readAsDataURL(f);
          }} className="text-xs" />
          <div><Label className="text-[11px]">Fit</Label>
            <select value={(layer as any).fit || "cover"} onChange={e => patch({ fit: e.target.value } as any)} className="h-8 w-full text-xs rounded border px-2">
              <option>cover</option><option>contain</option><option>fill</option>
            </select>
          </div>
          <div><Label className="text-[11px]">Border radius</Label><Input type="number" value={(layer as any).borderRadius || 0} onChange={e => patch({ borderRadius: parseInt(e.target.value || "0") } as any)} className="h-8" /></div>
        </div>
      )}

      {layer.type === "qr" && (
        <div className="space-y-2 pt-2 border-t">
          <p className="text-[11px] text-muted-foreground">QR is generated per guest from {`{{qr_code}}`}.</p>
          <div className="grid grid-cols-2 gap-2">
            <div><Label className="text-[11px]">Foreground</Label><Input type="color" value={layer.style.foregroundColor || "#000"} onChange={e => patch({ style: { ...layer.style, foregroundColor: e.target.value } } as any)} className="h-8 p-1" /></div>
            <div><Label className="text-[11px]">Background</Label><Input type="color" value={layer.style.backgroundColor || "#FFF"} onChange={e => patch({ style: { ...layer.style, backgroundColor: e.target.value } } as any)} className="h-8 p-1" /></div>
          </div>
          <div><Label className="text-[11px]">Padding</Label><Input type="number" value={layer.style.padding || 0} onChange={e => patch({ style: { ...layer.style, padding: parseInt(e.target.value || "0") } } as any)} className="h-8" /></div>
          <div><Label className="text-[11px]">Border radius</Label><Input type="number" value={layer.style.borderRadius || 0} onChange={e => patch({ style: { ...layer.style, borderRadius: parseInt(e.target.value || "0") } } as any)} className="h-8" /></div>
          {Math.min(layer.width, layer.height) < 120 && <p className="text-[11px] text-amber-600">Warning: QR is smaller than 120px. Increase size for reliable scanning.</p>}
        </div>
      )}
    </div>
  );
}
