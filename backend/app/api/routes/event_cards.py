"""Event card editor + pledge thank-you card delivery.

All endpoints are mounted under the default ``/api/v1`` prefix.

Card templates live on disk under ``backend/app/static/cards/<category>/``.
Each category folder contains one or more SVG files plus optional fonts
and a ``metadata.json`` describing editable fields. The scanner registers
every template into the ``card_templates`` DB table on demand so saved
``event_cards`` rows can reference a stable UUID.

SVG editing is restricted to the editable_fields whitelist in metadata.json
AND the SVG element must carry ``data-editable="true"``. The contributor
placeholder is never written by the editor; it is only substituted at
delivery time.
"""
from __future__ import annotations

import json
import os
import base64
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, BackgroundTasks, Body, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, Response
from sqlalchemy import and_
from sqlalchemy.orm import Session, joinedload

from core.database import get_db
from models import (
    CardTemplate,
    Event,
    EventCard,
    EventContributor,
    SentEventCard,
    User,
    UserSetting,
)
from utils.auth import get_current_user
from utils.card_storage import get_card_storage
from utils.card_render_cache import (
    read_text_cached,
    font_data_uri,
    get_font_face_block,
    set_font_face_block,
)
from utils.helpers import standard_response

router = APIRouter(tags=["Event Cards"])

# ──────────────────────────────────────────────
# Storage backend (filesystem today; swap via NURU_CARDS_STORAGE)
# ──────────────────────────────────────────────

_storage = get_card_storage()
_SAFE_NAME = re.compile(r"^[A-Za-z0-9 _.-]+$")
_SAFE_SLUG = re.compile(r"^[A-Za-z0-9_-]+$")


def _font_media_type_and_format(abs_path: str | Path, filename: str) -> tuple[str, str]:
    suffix = Path(filename).suffix.lower()
    media_type = {
        ".svg": "image/svg+xml",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".otf": "font/otf",
        ".woff": "font/woff",
        ".woff2": "font/woff2",
    }.get(suffix)
    css_format = {
        ".otf": "opentype",
        ".woff": "woff",
        ".woff2": "woff2",
    }.get(suffix)
    if suffix == ".ttf":
        try:
            header = Path(abs_path).read_bytes()[:4]
        except Exception:
            header = b""
        if header == b"ttcf":
            return "font/collection", "collection"
        return "font/ttf", "truetype"
    return media_type or "application/octet-stream", css_format or "truetype"


def _validate_category(category: str) -> str:
    if not category or not _SAFE_SLUG.match(category):
        raise HTTPException(status_code=400, detail="Invalid category")
    if category not in _storage.list_categories():
        raise HTTPException(status_code=404, detail="Category not found")
    return category


def _read_metadata(category: str) -> Dict[str, Any]:
    rel = f"{category}/metadata.json"
    if not _storage.exists(rel):
        return {}
    try:
        return json.loads(_storage.read_text(rel))
    except Exception:
        return {}


def _list_categories() -> List[Dict[str, Any]]:
    out = []
    for cat in _storage.list_categories():
        meta = _read_metadata(cat)
        svgs = [f for f in _storage.list_category_files(cat) if f.lower().endswith(".svg")]
        if not svgs:
            continue
        out.append({
            "category": cat,
            "label": meta.get("category_label") or cat.replace("-", " ").title(),
            "templates_count": len(svgs),
        })
    return out


def _human_template_name(stem: str) -> str:
    """
    Convert file names like:
    send_off_invitation_01
    wedding_invitation_02

    into:
    Send Off Invitation 01
    Wedding Invitation 02
    """
    return stem.replace("_", " ").replace("-", " ").title()


def _list_templates_in(category: str) -> List[Dict[str, Any]]:
    _validate_category(category)
    shared_meta = _read_metadata(category)
    files = _storage.list_category_files(category)
    svgs = sorted([f for f in files if f.lower().endswith(".svg")])
    out = []

    seen_slugs = set()

    for svg_name in svgs:
        stem = Path(svg_name).stem
        per_rel = f"{category}/{stem}.json"
        has_per_template_meta = _storage.exists(per_rel)

        if has_per_template_meta:
            try:
                template_meta = json.loads(_storage.read_text(per_rel))
            except Exception:
                template_meta = {}
        else:
            template_meta = {}

        # Merge shared metadata with per-template metadata.
        # Shared metadata gives common fields, fonts, QR placement, etc.
        # Per-template metadata can override name, slug, thumbnail, fields, etc.
        m = {
            **shared_meta,
            **template_meta,
        }

        # Slug should only come from per-template JSON.
        # Shared metadata.json must not force every SVG to share one slug.
        slug = (
            template_meta.get("slug")
            if has_per_template_meta and template_meta.get("slug")
            else f"{category}-{stem}"
        )

        # Name should only come from per-template JSON.
        # If no per-template name exists, generate it from SVG filename.
        display_name = (
            template_meta.get("name")
            if has_per_template_meta and template_meta.get("name")
            else _human_template_name(stem)
        )

        if slug in seen_slugs:
            raise HTTPException(
                status_code=500,
                detail=f"Duplicate card template slug detected: {slug}",
            )
        seen_slugs.add(slug)

        out.append({
            "category": category,
            "slug": slug,
            "name": display_name,
            "svg_file": svg_name,
            "thumbnail_file": m.get("thumbnail_file"),
            "editable_fields": m.get("editable_fields", []),
            "contributor_placeholder_id": m.get("contributor_placeholder_id"),
            "locked_ids": m.get("locked_ids", []),
            "fonts": m.get("fonts", []),
            "qr_placement": m.get("qr_placement"),
            "view_box": m.get("view_box"),
            "preserve_text_positions": bool(m.get("preserve_text_positions")),
            "replace_defaults_in_preview": bool(m.get("replace_defaults_in_preview")),
            "recipient_noun": m.get("recipient_noun"),
            "recipient_source": (m.get("recipient_source") or "contributors"),
            "recipient_filter": m.get("recipient_filter") or [],
        })

    return out


def _get_or_register_template(db: Session, category: str, slug: str) -> CardTemplate:
    found = next((t for t in _list_templates_in(category) if t["slug"] == slug), None)
    if not found:
        raise HTTPException(status_code=404, detail="Template not found")
    row = db.query(CardTemplate).filter(CardTemplate.slug == slug).first()
    if row:
        # keep metadata fresh on each access — cheap and avoids stale fields
        row.metadata_json = found
        row.svg_path = f"{category}/{found['svg_file']}"
        row.name = found["name"]
        row.category = category
        db.commit()
        return row
    row = CardTemplate(
        category=category,
        slug=slug,
        name=found["name"],
        svg_path=f"{category}/{found['svg_file']}",
        thumbnail_path=(f"{category}/{found['thumbnail_file']}" if found.get("thumbnail_file") else None),
        metadata_json=found,
        is_active=True,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


# ──────────────────────────────────────────────
# SVG safety + editing
# ──────────────────────────────────────────────

_SCRIPT_RE = re.compile(r"<script[\s\S]*?</script>", re.IGNORECASE)
_ON_ATTR_RE = re.compile(r"\son[a-z]+\s*=\s*\"[^\"]*\"", re.IGNORECASE)


def _sanitize_svg(svg: str) -> str:
    svg = re.sub(r"<\?xml[\s\S]*?\?>", "", svg, flags=re.IGNORECASE)
    svg = re.sub(r"<!DOCTYPE[\s\S]*?\]>", "", svg, flags=re.IGNORECASE)
    svg = re.sub(r"<!DOCTYPE[^>]*>", "", svg, flags=re.IGNORECASE)
    svg = _SCRIPT_RE.sub("", svg)
    svg = _ON_ATTR_RE.sub("", svg)
    return svg.strip()


def _center_text_element(svg: str, element_id: str, center_x: float = 561.0) -> str:
    """Keep dynamic single-line text visually centred in the card artwork."""
    id_part = re.escape(element_id)

    def patch_open(match: re.Match) -> str:
        open_tag = match.group(1)
        open_tag = re.sub(
            r'transform="matrix\(1\s+0\s+0\s+1\s+[-0-9.]+\s+([-0-9.]+)\)"',
            lambda m: f'transform="matrix(1 0 0 1 {center_x:g} {m.group(1)})"',
            open_tag,
            count=1,
        )
        if 'text-anchor=' in open_tag:
            open_tag = re.sub(r'text-anchor="[^"]*"', 'text-anchor="middle"', open_tag, count=1)
        else:
            open_tag = open_tag[:-1] + ' text-anchor="middle">'
        return open_tag

    return re.sub(r'(<(?:text|tspan)\b[^>]*\bid\s*=\s*"' + id_part + r'"[^>]*>)', patch_open, svg, count=1, flags=re.IGNORECASE)


def _inject_template_font_faces(svg: str, tpl: CardTemplate, mode: str = "file") -> str:
    meta = tpl.metadata_json or {}
    fonts = meta.get("fonts") or []
    if not fonts:
        return svg
    # Resolve absolute font paths once (cheap) and try the cached <style> block.
    resolved: List[tuple[str, str, str, str, bool]] = []  # (abs_path, mime, fmt, filename, is_italic)
    for filename in fonts:
        if not isinstance(filename, str) or not _SAFE_NAME.match(filename):
            continue
        rel = f"{tpl.category}/{filename}"
        abs_path = _storage.absolute_path(rel)
        if not abs_path:
            continue
        mime, fmt = _font_media_type_and_format(abs_path, filename)
        resolved.append((abs_path, mime, fmt, filename, "italic" in filename.lower()))
    if not resolved:
        return svg
    cache_key_paths = tuple(sorted(r[0] for r in resolved))
    cached_block = get_font_face_block(str(tpl.id), mode, cache_key_paths)
    if cached_block is not None:
        return re.sub(r"</svg>\s*$", f"{cached_block}</svg>", svg, flags=re.IGNORECASE)
    blocks: List[str] = []
    for abs_path, mime, fmt, filename, is_italic in resolved:
        bare = re.sub(r"\.(ttf|otf|woff2?|eot)$", "", filename, flags=re.IGNORECASE)
        spaced = re.sub(r"\s*Italic\s*$", "", bare, flags=re.IGNORECASE).strip()
        squashed = re.sub(r"\s+", "", spaced)
        if mode == "data":
            url = font_data_uri(abs_path, mime)
        else:
            url = Path(abs_path).resolve().as_uri()
        for family in dict.fromkeys([spaced, squashed]):
            if family:
                blocks.append(
                    f"@font-face{{font-family:'{family}';src:url('{url}') format('{fmt}');font-weight:400;font-style:{'italic' if is_italic else 'normal'};}}"
                )
    if not blocks:
        return svg
    style_block = f"<style>{''.join(blocks)}</style>"
    set_font_face_block(str(tpl.id), mode, cache_key_paths, style_block)
    return re.sub(r"</svg>\s*$", f"{style_block}</svg>", svg, flags=re.IGNORECASE)


def _apply_text_edits(svg: str, edits: Dict[str, str], allowed_ids: List[str]) -> str:
    """Replace text content of <text id="…"> / <tspan id="…"> nodes when the
    id is in ``allowed_ids`` AND the element carries data-editable="true".
    Only inner text is replaced. Element structure is preserved.
    """
    if not edits:
        return svg
    for eid, value in edits.items():
        if eid not in allowed_ids:
            continue
        safe_val = (str(value or "")
                    .replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;"))
        # Match either <tspan ...>...</tspan> or <text ...>...</text> where
        # the open tag carries id="<eid>" AND data-editable="true".
        pattern = re.compile(
            r'(<(text|tspan)\b[^>]*\bid\s*=\s*"' + re.escape(eid) +
            r'"[^>]*\bdata-editable\s*=\s*"true"[^>]*>)([\s\S]*?)(</\2>)',
            re.IGNORECASE,
        )
        svg = pattern.sub(lambda m: f"{m.group(1)}{safe_val}{m.group(4)}", svg)
    return svg


def _render_qr_data_uri(payload: str, size_px: int = 512) -> Optional[str]:
    """Render `payload` as a high-error-correction QR PNG and return a
    ``data:image/png;base64,…`` URI suitable for inlining in an SVG.
    Returns ``None`` if the `qrcode` package isn't available."""
    if not payload:
        return None
    try:
        import qrcode  # type: ignore
        from io import BytesIO
        qr = qrcode.QRCode(
            error_correction=qrcode.constants.ERROR_CORRECT_H,
            box_size=10,
            border=1,
        )
        qr.add_data(payload)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        # Upscale/downscale to the requested pixel size for crispness.
        try:
            img = img.resize((size_px, size_px))
        except Exception:
            pass
        buf = BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        return f"data:image/png;base64,{b64}"
    except Exception as exc:
        print(f"[event_cards] qr render failed: {exc!r}")
        return None


def _inject_qr_image(svg: str, qr_placement: Optional[Dict[str, Any]], payload: str) -> str:
    """Append an ``<image>`` element rendering the QR at the metadata
    ``qr_placement`` rectangle, immediately before ``</svg>``. Existing
    placeholder QR artwork in the template is left alone — the inlined
    image simply overlays it at the same coordinates."""
    if not qr_placement or not payload:
        return svg
    try:
        x = float(qr_placement.get("x", 0))
        y = float(qr_placement.get("y", 0))
        w = float(qr_placement.get("width", 0))
        h = float(qr_placement.get("height", 0))
    except Exception:
        return svg
    if w <= 0 or h <= 0:
        return svg
    data_uri = _render_qr_data_uri(payload, size_px=max(256, int(round(max(w, h) * 6))))
    if not data_uri:
        return svg
    img_tag = (
        f'<image x="{x}" y="{y}" width="{w}" height="{h}" '
        f'preserveAspectRatio="xMidYMid meet" '
        f'href="{data_uri}" xlink:href="{data_uri}" />'
    )
    # Inject before the LAST </svg> close tag.
    idx = svg.rfind("</svg>")
    if idx == -1:
        return svg
    return svg[:idx] + img_tag + svg[idx:]


def _render_event_card_svg(
    db: Session,
    event: Event,
    category: str,
    contributor_name: Optional[str] = None,
    qr_payload: Optional[str] = None,
) -> tuple[str, EventCard, CardTemplate]:
    ec = (
        db.query(EventCard)
        .filter(EventCard.event_id == event.id, EventCard.category == category, EventCard.is_active.is_(True))
        .first()
    )
    if not ec:
        raise HTTPException(status_code=404, detail="No card configured for this event yet.")
    tpl = db.query(CardTemplate).filter(CardTemplate.id == ec.card_template_id).first()
    if not tpl:
        raise HTTPException(status_code=404, detail="Card template missing.")
    if not _storage.exists(tpl.svg_path):
        raise HTTPException(status_code=500, detail="Card asset missing.")
    _abs = _storage.absolute_path(tpl.svg_path)
    raw_text = read_text_cached(_abs) if _abs else _storage.read_text(tpl.svg_path)
    raw = _sanitize_svg(raw_text)
    meta = tpl.metadata_json or {}
    allowed = [f["id"] for f in meta.get("editable_fields", []) if f.get("id")]
    svg = _apply_text_edits(raw, ec.custom_text_values or {}, allowed)
    preserve_text_positions = bool(meta.get("preserve_text_positions"))
    # Legacy cards need runtime centering; optimized SVG templates keep their
    # author-provided coordinates exactly to avoid shifting the artwork text.
    if not preserve_text_positions:
        for fid in allowed:
            svg = _center_text_element(svg, fid)
    if contributor_name:
        placeholder = meta.get("contributor_placeholder_id") or "contributor_name_text"
        pattern = re.compile(
            r'(<(text|tspan)\b[^>]*\bid\s*=\s*"' + re.escape(placeholder) + r'"[^>]*>)([\s\S]*?)(</\2>)',
            re.IGNORECASE,
        )
        safe_name = (contributor_name.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        prefix_raw = ((ec.custom_text_values or {}).get("__guest_name_prefix") or "").strip()
        if prefix_raw:
            safe_prefix = prefix_raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            safe_name = f"{safe_prefix} {safe_name}"
        svg = pattern.sub(lambda m: f"{m.group(1)}{safe_name}{m.group(4)}", svg)
        if not preserve_text_positions:
            svg = _center_text_element(svg, placeholder)
    if qr_payload:
        svg = _inject_qr_image(svg, meta.get("qr_placement"), qr_payload)
    svg = _inject_template_font_faces(svg, tpl, mode="data")
    return svg, ec, tpl



def _render_png_bytes(svg: str, tpl: CardTemplate, width: int = 1080) -> Optional[bytes]:
    """Best-effort SVG → PNG using cairosvg with the template's font dir.
    Returns None if cairosvg isn't installed or rendering fails — callers
    should fall back to SMS-only delivery.
    """
    try:
        import cairosvg  # type: ignore
    except Exception:
        return None
    font_dir = _storage.open_font_dir(tpl.category)
    prev_fc = os.environ.get("FONTCONFIG_PATH")
    prev_xdg = os.environ.get("XDG_DATA_HOME")
    os.environ["XDG_DATA_HOME"] = str(font_dir)
    try:
        return cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=width)
    except Exception as exc:
        print(f"[event_cards] cairosvg render failed: {exc!r}")
        return None
    finally:
        if prev_fc is not None:
            os.environ["FONTCONFIG_PATH"] = prev_fc
        if prev_xdg is not None:
            os.environ["XDG_DATA_HOME"] = prev_xdg
        else:
            os.environ.pop("XDG_DATA_HOME", None)


def _public_api_base(host: str) -> str:
    """Public API host used for Meta-fetchable card URLs."""
    configured = os.getenv("API_BASE_URL", "").rstrip("/")
    if configured:
        configured = configured.replace("https://api.nuru.tz", "https://nuruapi.nuru.tz")
        configured = configured.replace("http://api.nuru.tz", "https://nuruapi.nuru.tz")
        return configured
    clean_host = (host or "nuru.tz").strip().removeprefix("www.")
    if clean_host.startswith("nuru."):
        return f"https://nuruapi.{clean_host}"
    return f"https://nuruapi.nuru.tz"


# ──────────────────────────────────────────────
# Permissions
# ──────────────────────────────────────────────

def _assert_event_manager(db: Session, event_id: str, user: User) -> Event:
    try:
        eid = uuid.UUID(str(event_id))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid event id")
    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if str(event.organizer_id) != str(user.id) and str(getattr(event, "event_owner_user_id", "")) != str(user.id):
        # accept committee permission with can_manage_contributions
        try:
            from models import EventCommitteeMember
            cm = db.query(EventCommitteeMember).filter(
                and_(EventCommitteeMember.event_id == event.id, EventCommitteeMember.member_user_id == user.id)
            ).first()
            if not cm:
                raise HTTPException(status_code=403, detail="Only the event organiser can manage cards.")
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=403, detail="Only the event organiser can manage cards.")
    return event


# ──────────────────────────────────────────────
# Catalogue endpoints (must be defined BEFORE dynamic event paths)
# ──────────────────────────────────────────────

@router.get("/cards/categories")
def list_categories(_user: User = Depends(get_current_user)):
    return standard_response(True, "OK", {"categories": _list_categories()})


@router.get("/cards/categories/{category}/templates")
def list_templates(category: str, db: Session = Depends(get_db), _user: User = Depends(get_current_user)):
    tpls = _list_templates_in(category)
    # Register each so frontend can reference DB ids
    for t in tpls:
        _get_or_register_template(db, category, t["slug"])
    out = []
    for t in tpls:
        row = db.query(CardTemplate).filter(CardTemplate.slug == t["slug"]).first()
        out.append({
            "id": str(row.id) if row else None,
            **t,
            "svg_url": f"/api/v1/cards/templates/{t['slug']}/asset/{t['svg_file']}",
            "thumbnail_url": (f"/api/v1/cards/templates/{t['slug']}/asset/{t['thumbnail_file']}"
                              if t.get("thumbnail_file") else None),
        })
    return standard_response(True, "OK", {"category": category, "templates": out})


@router.get("/cards/templates/{slug}")
def get_template(slug: str, db: Session = Depends(get_db), _user: User = Depends(get_current_user)):
    row = db.query(CardTemplate).filter(CardTemplate.slug == slug).first()
    if not row:
        # search disk for this slug
        for cat in _list_categories():
            for t in _list_templates_in(cat["category"]):
                if t["slug"] == slug:
                    row = _get_or_register_template(db, cat["category"], slug)
                    break
            if row:
                break
    if not row:
        raise HTTPException(status_code=404, detail="Template not found")
    svg = _sanitize_svg(_storage.read_text(row.svg_path))
    return standard_response(True, "OK", {
        "id": str(row.id),
        "slug": row.slug,
        "category": row.category,
        "name": row.name,
        "metadata": row.metadata_json or {},
        "svg": svg,
    })


@router.get("/cards/templates/{slug}/asset/{filename}")
def get_template_asset(slug: str, filename: str, db: Session = Depends(get_db)):
    if not _SAFE_NAME.match(filename):
        raise HTTPException(status_code=400, detail="Invalid filename")
    row = db.query(CardTemplate).filter(CardTemplate.slug == slug).first()
    if not row:
        raise HTTPException(status_code=404, detail="Template not found")
    rel = f"{row.category}/{filename}"
    if not _storage.exists(rel):
        raise HTTPException(status_code=404, detail="Asset not found")
    suffix = Path(filename).suffix.lower()
    abs_path = _storage.absolute_path(rel)
    mt, _ = _font_media_type_and_format(abs_path or rel, filename)
    if suffix == ".svg":
        svg = _inject_template_font_faces(_sanitize_svg(_storage.read_text(rel)), row, mode="data")
        return Response(content=svg, media_type=mt)
    if abs_path:
        return FileResponse(abs_path, media_type=mt)
    return Response(content=_storage.read_bytes(rel), media_type=mt)


# ──────────────────────────────────────────────
# Event-scoped endpoints
# ──────────────────────────────────────────────

@router.get("/events/{event_id}/cards")
def list_event_cards(event_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    event = _assert_event_manager(db, event_id, current_user)
    rows = db.query(EventCard).filter(EventCard.event_id == event.id, EventCard.is_active.is_(True)).all()
    data = []
    for ec in rows:
        tpl = db.query(CardTemplate).filter(CardTemplate.id == ec.card_template_id).first()
        data.append({
            "id": str(ec.id),
            "category": ec.category,
            "card_template_id": str(ec.card_template_id),
            "card_template_slug": tpl.slug if tpl else None,
            "card_template_name": tpl.name if tpl else None,
            "custom_text_values": ec.custom_text_values or {},
            "updated_at": ec.updated_at.isoformat() if ec.updated_at else None,
        })
    return standard_response(True, "OK", {"event_cards": data})


@router.put("/events/{event_id}/cards")
def upsert_event_card(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _assert_event_manager(db, event_id, current_user)
    slug = (body.get("card_template_slug") or "").strip()
    category = (body.get("category") or "").strip()
    tpl_id_raw = body.get("card_template_id")
    if not category:
        raise HTTPException(status_code=400, detail="category is required")
    tpl: Optional[CardTemplate] = None
    if tpl_id_raw:
        try:
            tpl = db.query(CardTemplate).filter(CardTemplate.id == uuid.UUID(str(tpl_id_raw))).first()
        except Exception:
            tpl = None
    if not tpl and slug:
        tpl = _get_or_register_template(db, category, slug)
    if not tpl:
        raise HTTPException(status_code=400, detail="card_template_id or card_template_slug is required")
    if tpl.category != category:
        raise HTTPException(status_code=400, detail="Category does not match template")

    meta = tpl.metadata_json or {}
    allowed_ids = {f["id"] for f in meta.get("editable_fields", []) if f.get("id")}
    max_len_by_id = {f["id"]: int(f.get("max_length") or 1000) for f in meta.get("editable_fields", [])}
    locked = set(meta.get("locked_ids", [])) | {meta.get("contributor_placeholder_id") or "contributor_name_text"}

    raw_values = body.get("custom_text_values") or {}
    if not isinstance(raw_values, dict):
        raise HTTPException(status_code=400, detail="custom_text_values must be an object")
    clean: Dict[str, str] = {}
    for k, v in raw_values.items():
        if k in locked:
            continue
        if k not in allowed_ids:
            continue
        s = str(v or "")
        ml = max_len_by_id.get(k, 1000)
        if len(s) > ml:
            s = s[:ml]
        clean[k] = s

    existing = (
        db.query(EventCard)
        .filter(EventCard.event_id == event.id, EventCard.category == category, EventCard.is_active.is_(True))
        .first()
    )
    if existing:
        existing.card_template_id = tpl.id
        existing.custom_text_values = clean
        existing.updated_by_user_id = current_user.id
        existing.updated_at = datetime.utcnow()
        ec = existing
    else:
        ec = EventCard(
            event_id=event.id,
            card_template_id=tpl.id,
            category=category,
            custom_text_values=clean,
            created_by_user_id=current_user.id,
            updated_by_user_id=current_user.id,
            is_active=True,
        )
        db.add(ec)
    db.commit()
    db.refresh(ec)
    return standard_response(True, "Card saved.", {
        "id": str(ec.id),
        "category": ec.category,
        "card_template_id": str(ec.card_template_id),
        "card_template_slug": tpl.slug,
        "custom_text_values": ec.custom_text_values or {},
    })


@router.post("/events/{event_id}/cards/{category}/upload-render")
async def upload_browser_rendered_card(
    event_id: str,
    category: str,
    recipient_id: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload browser-rendered card bytes to Nuru's own backend storage
    (the same host used by KYC/media uploads). Meta can fetch these URLs
    reliably for WhatsApp media headers across browsers."""
    import httpx
    from core.config import UPLOAD_SERVICE_URL

    event = _assert_event_manager(db, event_id, current_user)
    active_card = (
        db.query(EventCard)
        .filter(and_(EventCard.event_id == event.id, EventCard.category == category, EventCard.is_active.is_(True)))
        .first()
    )
    if not active_card:
        raise HTTPException(status_code=404, detail="No card configured for this event yet.")
    if not file or not file.filename:
        raise HTTPException(status_code=400, detail="file is required")
    try:
        uuid.UUID(str(recipient_id))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid recipient id")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty card image")
    if len(content) > 8 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Card image is too large")

    base_name = uuid.uuid4().hex
    unique_name = f"{base_name}.png"
    target_path = f"nuru/uploads/cards/{event.id}/{active_card.id}/{recipient_id}/"
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                UPLOAD_SERVICE_URL,
                data={"target_path": target_path},
                files={"file": (unique_name, content, file.content_type or "image/png")},
                timeout=30,
            )
        result = resp.json() if resp is not None else {}
    except Exception as e:  # noqa: BLE001
        print(f"[event_cards] nuru upload failed: {e}")
        raise HTTPException(status_code=502, detail="Card upload failed")
    if not result.get("success"):
        raise HTTPException(status_code=502, detail=result.get("message") or "Card upload failed")
    url = (result.get("data") or {}).get("url")
    if not url:
        raise HTTPException(status_code=502, detail="Card upload returned no URL")

    # Generate the WhatsApp-safe JPEG sibling now so dispatch can send it
    # without any extra latency. Meta rejects large/alpha PNG headers
    # with error 131053 — the flattened JPG fixes that.
    whatsapp_url = url
    wa_size = None
    wa_width = None
    wa_height = None
    wa_error = None
    try:
        from utils.whatsapp_media import prepare_whatsapp_jpeg_bytes
        jpg_bytes, wa_width, wa_height = prepare_whatsapp_jpeg_bytes(content)
        wa_filename = f"{base_name}.wa.jpg"
        async with httpx.AsyncClient() as client:
            wa_resp = await client.post(
                UPLOAD_SERVICE_URL,
                data={"target_path": target_path},
                files={"file": (wa_filename, jpg_bytes, "image/jpeg")},
                timeout=30,
            )
        wa_result = wa_resp.json() if wa_resp is not None else {}
        if wa_resp.is_success and wa_result.get("success"):
            whatsapp_url = (wa_result.get("data") or {}).get("url") or url
            wa_size = len(jpg_bytes)
        else:
            wa_error = (wa_result.get("message")
                        or f"http {getattr(wa_resp, 'status_code', '?')}")
    except Exception as e:  # noqa: BLE001
        wa_error = str(e)
    print(
        f"[event_cards] card upload ok png_url={url} whatsapp_url={whatsapp_url} "
        f"png_bytes={len(content)} wa_bytes={wa_size} wa_dim={wa_width}x{wa_height} "
        f"wa_error={wa_error!r}"
    )

    return standard_response(True, "Card image uploaded.", {
        "url": url,
        "path": target_path + unique_name,
        "whatsapp_url": whatsapp_url,
        "whatsapp_bytes": wa_size,
        "whatsapp_dimensions": (
            {"width": wa_width, "height": wa_height} if wa_width and wa_height else None
        ),
    })


@router.get("/events/{event_id}/cards/{category}/preview.svg")
def preview_event_card_svg(
    event_id: str,
    category: str,
    contributor_id: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _assert_event_manager(db, event_id, current_user)
    name = None
    if contributor_id:
        try:
            ec = db.query(EventContributor).options(joinedload(EventContributor.contributor)).filter(
                EventContributor.id == uuid.UUID(contributor_id), EventContributor.event_id == event.id
            ).first()
            if ec:
                ev_name = (getattr(ec, "display_name", None) or "").strip()
                name = ev_name or (ec.contributor.name if ec.contributor else None)
        except Exception:
            pass
    svg, _ec, _tpl = _render_event_card_svg(db, event, category, contributor_name=name)
    return Response(content=svg, media_type="image/svg+xml")


@router.get("/events/{event_id}/cards/{category}/preview.png")
def preview_event_card_png(
    event_id: str,
    category: str,
    contributor_id: Optional[str] = Query(default=None),
    width: int = Query(default=1080, ge=320, le=2160),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _assert_event_manager(db, event_id, current_user)
    name = None
    if contributor_id:
        try:
            ec = db.query(EventContributor).options(joinedload(EventContributor.contributor)).filter(
                EventContributor.id == uuid.UUID(contributor_id), EventContributor.event_id == event.id
            ).first()
            if ec:
                ev_name = (getattr(ec, "display_name", None) or "").strip()
                name = ev_name or (ec.contributor.name if ec.contributor else None)
        except Exception:
            pass
    svg, _ec, tpl = _render_event_card_svg(db, event, category, contributor_name=name)
    png = _render_png_bytes(svg, tpl, width=width)
    if not png:
        raise HTTPException(status_code=503, detail="PNG renderer unavailable on this server.")
    return Response(content=png, media_type="image/png")


@router.post("/events/{event_id}/cards/{category}/send")
def send_pledge_thank_you_cards(
    event_id: str,
    category: str,
    body: dict = Body(...),
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _assert_event_manager(db, event_id, current_user)
    dispatch_event_id = event.id
    dispatch_sender_user_id = current_user.id

    # When True, we create SentEventCard rows in 'prepared' state and skip
    # the WhatsApp/SMS dispatch entirely. The organiser can later browse
    # them under the Prepared Cards tab and send them in bulk.
    prepare_only = bool(body.get("prepare_only"))

    # mode controls duplicate handling:
    #   "fresh"          → always (re)act on every selected recipient.
    #                      For prepare_only this overwrites the existing
    #                      prepared row (preserving its stable URL behind
    #                      the same id when the browser uploads to the same
    #                      key, otherwise replacing rendered_card_url).
    #                      For send this dispatches again even to people
    #                      who were sent before.
    #   "skip_existing"  → recipients who already have a usable card row
    #                      are silently dropped before any work runs.
    # Default is "fresh" to preserve the previous behaviour for older
    # frontends that don't pass the field.
    mode = (body.get("mode") or "fresh").strip().lower()
    if mode not in ("fresh", "skip_existing"):
        mode = "fresh"

    raw_guest_ids = body.get("guest_ids")
    raw_contrib_ids = body.get("contributor_ids")
    is_guest_dispatch = bool(raw_guest_ids)


    if is_guest_dispatch:
        if not isinstance(raw_guest_ids, list) or not raw_guest_ids:
            raise HTTPException(status_code=400, detail="guest_ids is required")
        try:
            ids = [uuid.UUID(str(x)) for x in raw_guest_ids]
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid guest id in list")
    else:
        if not isinstance(raw_contrib_ids, list) or not raw_contrib_ids:
            raise HTTPException(status_code=400, detail="contributor_ids is required")
        try:
            ids = [uuid.UUID(str(x)) for x in raw_contrib_ids]
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid contributor id in list")

    # Frontend can render the final PNG in the browser (matches preview
    # exactly, avoids 12 MB Illustrator SVG rasterisation on the VPS) and
    # upload one URL per recipient. For invitation cards (guests), the
    # browser also bakes the per-guest QR into the rendered PNG, so the
    # uploaded URL is the canonical artwork — the server-side cairosvg
    # fallback (which strips custom fonts/styles) is only used when the
    # client could not pre-render.
    raw_pre = body.get("pre_rendered_images") or {}
    pre_rendered: Dict[str, str] = {}
    if isinstance(raw_pre, dict):
        for k, v in raw_pre.items():
            if isinstance(v, str) and v.strip():
                pre_rendered[str(k)] = v.strip()

    active_card = (
        db.query(EventCard)
        .filter(and_(EventCard.event_id == dispatch_event_id, EventCard.category == category, EventCard.is_active.is_(True)))
        .first()
    )
    if not active_card:
        raise HTTPException(status_code=404, detail="No card configured for this event yet.")
    dispatch_event_card_id = active_card.id

    # ── skip_existing pre-filter ──
    # "Skip existing" means: drop recipients who already have a row that
    # represents the kind of work we're about to do. For prepare_only we
    # drop only existing prepared rows. For send we drop only rows
    # that were actually successfully delivered to WhatsApp/SMS (so a
    # previous failed send is retried automatically).
    skipped_existing_ids: List[str] = []
    if mode == "skip_existing":
        skip_statuses = {"prepared"} if prepare_only else {"sent", "delivered", "read"}
        column = SentEventCard.guest_attendee_id if is_guest_dispatch else SentEventCard.contributor_id
        # Match by CATEGORY (via the EventCard join), not by the active
        # EventCard id — older sends may live under a previous EventCard /
        # template row for the same category and must still be skipped.
        existing_rows = (
            db.query(column, SentEventCard.delivery_status)
            .join(EventCard, SentEventCard.event_card_id == EventCard.id)
            .filter(
                SentEventCard.event_id == dispatch_event_id,
                EventCard.category == category,
                column.in_(ids),
            )
            .all()
        )
        already_done: set = set()
        for rid, status in existing_rows:
            if rid is None:
                continue
            if status and str(status) in skip_statuses:
                already_done.add(rid)
        if already_done:
            skipped_existing_ids = [str(x) for x in already_done]
            ids = [i for i in ids if i not in already_done]
        if not ids:
            return standard_response(
                True,
                "Nothing to do — every selected recipient already has a card.",
                {
                    "prepared": 0,
                    "queued": 0,
                    "skipped_existing": skipped_existing_ids,
                    "sent_ids": [],
                },
            )


    sent_card_ids: List[str] = []
    sid_to_pre_rendered: Dict[str, str] = {}

    if is_guest_dispatch:
        # Resolve event attendees + their invitation codes for QR payloads.
        from models import EventAttendee, EventInvitation, UserContributor
        attendees = (
            db.query(EventAttendee)
            .filter(and_(EventAttendee.event_id == dispatch_event_id, EventAttendee.id.in_(ids)))
            .all()
        )
        if not attendees:
            raise HTTPException(status_code=404, detail="No selected guests found on this event.")
        for att in attendees:
            # Display name — prefer the organiser-supplied common_name (e.g.
            # "Mr & Mrs Mpinzile") for cards, then fall back to the canonical
            # resolver from user_events.
            common = (getattr(att, "common_name", None) or "").strip()
            if common:
                display_name = common
            else:
                try:
                    from api.routes.user_events import _resolve_guest_name as _grn
                    display_name = _grn(db, att) or att.guest_name or "Guest"
                except Exception:
                    display_name = att.guest_name or "Guest"
            # Phone — attendee → linked user → linked contributor → guest_phone.
            phone = None
            if att.attendee_id:
                u = db.query(User).filter(User.id == att.attendee_id).first()
                phone = (getattr(u, "phone", None) if u else None)
            if not phone and att.contributor_id:
                c = db.query(UserContributor).filter(UserContributor.id == att.contributor_id).first()
                phone = c.phone if c else None
            if not phone:
                phone = att.guest_phone
            # QR payload — invitation_code if present, else attendee id.
            qr_payload = None
            if att.invitation_id:
                inv = db.query(EventInvitation).filter(EventInvitation.id == att.invitation_id).first()
                qr_payload = inv.invitation_code if inv and inv.invitation_code else None
            if not qr_payload:
                qr_payload = str(att.id)
            existing = None
            if prepare_only:
                existing = (
                    db.query(SentEventCard)
                    .filter(
                        SentEventCard.event_id == dispatch_event_id,
                        SentEventCard.event_card_id == dispatch_event_card_id,
                        SentEventCard.guest_attendee_id == att.id,
                        SentEventCard.delivery_status == "prepared",
                    )
                    .first()
                )
            if existing:
                existing.recipient_name = display_name
                existing.recipient_phone = phone
                existing.recipient_qr_payload = qr_payload
                existing.sent_by_user_id = dispatch_sender_user_id
                db.commit()
                sent_card_ids.append(str(existing.id))
                pre_url = pre_rendered.get(str(att.id))
                if pre_url:
                    sid_to_pre_rendered[str(existing.id)] = pre_url
                continue
            sent = SentEventCard(
                event_id=dispatch_event_id,
                guest_attendee_id=att.id,
                event_card_id=dispatch_event_card_id,
                recipient_name=display_name,
                recipient_phone=phone,
                recipient_qr_payload=qr_payload,
                delivery_status="pending",
                delivery_channel="whatsapp",
                sent_by_user_id=dispatch_sender_user_id,
            )
            db.add(sent)
            db.commit()
            db.refresh(sent)
            sent_card_ids.append(str(sent.id))
            pre_url = pre_rendered.get(str(att.id))
            if pre_url:
                sid_to_pre_rendered[str(sent.id)] = pre_url
    else:
        contributors = (
            db.query(EventContributor)
            .options(joinedload(EventContributor.contributor))
            .filter(and_(EventContributor.event_id == dispatch_event_id, EventContributor.id.in_(ids), EventContributor.pledge_amount > 0))
            .all()
        )
        if not contributors:
            raise HTTPException(status_code=404, detail="No selected contributors with a pending pledge were found on this event.")

        for ec in contributors:
            if not ec.contributor:
                continue
            # Display name priority: per-event override on EventContributor →
            # organiser-supplied common_name ("Mr & Mrs Mpinzile") → canonical
            # global contributor name → "Friend" fallback.
            ev_display = (getattr(ec, "display_name", None) or "").strip()
            contrib_common = (getattr(ec.contributor, "common_name", None) or "").strip()
            contrib_display = ev_display or contrib_common or (ec.contributor.name or "Friend")
            existing = None
            if prepare_only:
                existing = (
                    db.query(SentEventCard)
                    .filter(
                        SentEventCard.event_id == dispatch_event_id,
                        SentEventCard.event_card_id == dispatch_event_card_id,
                        SentEventCard.contributor_id == ec.id,
                        SentEventCard.delivery_status == "prepared",
                    )
                    .first()
                )
            if existing:
                existing.recipient_name = contrib_display
                existing.recipient_phone = ec.contributor.phone
                existing.sent_by_user_id = dispatch_sender_user_id
                db.commit()
                sent_card_ids.append(str(existing.id))
                pre_url = pre_rendered.get(str(ec.id))
                if pre_url:
                    sid_to_pre_rendered[str(existing.id)] = pre_url
                continue
            sent = SentEventCard(
                event_id=dispatch_event_id,
                contributor_id=ec.id,
                event_card_id=dispatch_event_card_id,
                recipient_name=contrib_display,
                recipient_phone=ec.contributor.phone,
                delivery_status="pending",
                delivery_channel="whatsapp",
                sent_by_user_id=dispatch_sender_user_id,
            )
            db.add(sent)
            db.commit()
            db.refresh(sent)
            sent_card_ids.append(str(sent.id))
            pre_url = pre_rendered.get(str(ec.id))
            if pre_url:
                sid_to_pre_rendered[str(sent.id)] = pre_url


    # ── Prepare-only path: stash rows under 'prepared' and stop here. ──
    # The browser-side pre-rendered URL (if any) is recorded on
    # ``rendered_card_url`` so the Prepared Cards tab can render a thumbnail
    # immediately without re-running the SVG renderer.
    if prepare_only:
        for sid in sent_card_ids:
            try:
                row = db.query(SentEventCard).filter(SentEventCard.id == uuid.UUID(sid)).first()
            except Exception:
                row = None
            if not row:
                continue
            row.delivery_status = "prepared"
            pre_url = sid_to_pre_rendered.get(sid)
            if pre_url:
                # Always overwrite with the latest pre-rendered URL so re-
                # preparing the same recipient replaces the existing card
                # rather than leaving a stale version behind.
                row.rendered_card_url = pre_url
        db.commit()
        return standard_response(
            True,
            f"Prepared {len(sent_card_ids)} cards.",
            {"prepared": len(sent_card_ids), "sent_ids": [str(x) for x in sent_card_ids]},
        )






    def _dispatch(dispatch_event_id: str, dispatch_category: str, dispatch_sent_card_ids: List[str], dispatch_sender_user_id: str, pre_rendered_map: Dict[str, str]):
        from core.database import SessionLocal
        from services.share_links import host_for_currency, can_send_sms_for_currency
        from utils.whatsapp import wa_pledge_thank_you_card
        from utils.sms import sms_pledge_thank_you_card

        # Attribute every WhatsApp log row created by this dispatch to the
        # user who clicked Send (background threads don't inherit the
        # per-request context set by the middleware).
        try:
            from utils.wa_logging import set_wa_log_context
            set_wa_log_context(user_id=dispatch_sender_user_id, event_id=dispatch_event_id)
        except Exception:  # noqa: BLE001
            pass

        s = SessionLocal()
        try:
            ev = s.query(Event).filter(Event.id == uuid.UUID(dispatch_event_id)).first()
            if not ev:
                for sid in dispatch_sent_card_ids:
                    row = s.query(SentEventCard).filter(SentEventCard.id == uuid.UUID(str(sid))).first()
                    if row:
                        row.delivery_status = "failed"
                        row.error_message = "Event not found during card dispatch."
                s.commit()
                return
            saved_card = (
                s.query(EventCard)
                .filter(and_(EventCard.event_id == ev.id, EventCard.category == dispatch_category, EventCard.is_active.is_(True)))
                .first()
            )
            tpl = s.query(CardTemplate).filter(CardTemplate.id == saved_card.card_template_id).first() if saved_card else None
            currency = None
            try:
                from models import Currency
                if getattr(ev, "currency_id", None):
                    cur = s.query(Currency).filter(Currency.id == ev.currency_id).first()
                    currency = cur.code if cur else None
            except Exception:
                pass
            sms_ok = can_send_sms_for_currency(currency)
            host = host_for_currency(currency)
            # Resolve language preference
            lang = "sw"
            try:
                settings = s.query(UserSetting).filter(UserSetting.user_id == uuid.UUID(dispatch_sender_user_id)).first()
                lang = (getattr(settings, "notification_language", None) or "sw").lower()[:2]
            except Exception:
                pass

            for sid in dispatch_sent_card_ids:
                row = s.query(SentEventCard).filter(SentEventCard.id == uuid.UUID(str(sid))).first()
                if not row:
                    continue
                if not saved_card or not tpl:
                    row.delivery_status = "failed"
                    row.error_message = "Card configuration missing during dispatch."
                    s.commit()
                    continue
                # Stable per-recipient card URL: always reuse the same
                # public token for (contributor, thank_you, event), so
                # re-sends overwrite the file behind a fixed URL instead
                # of minting new ones. See docs/card_url_mappings.md.
                from services.card_url_service import (
                    generate_or_replace_card,
                    _default_public_host,
                )
                from utils.whatsapp_cards import upload_card_png, upload_card_svg, upload_card_svg_url

                api_base = _public_api_base(host)
                fallback_image_url = f"{api_base}/api/v1/cards/public/{row.id}.png"
                landing_url = f"https://{host}/cards/{row.id}"

                # Per-recipient context: guest invitations carry a QR payload
                # and use a guest-scoped stable token; thank-you cards keep
                # the legacy contributor-scoped token.
                is_guest_row = bool(row.guest_attendee_id)
                qr_payload = row.recipient_qr_payload if is_guest_row else None
                if is_guest_row:
                    rec_type = "guest"
                    rec_id = str(row.guest_attendee_id)
                    purpose = "invitation"
                    rel_type = "attendee"
                    rel_id = str(row.guest_attendee_id)
                else:
                    rec_type = "contributor"
                    rec_id = str(row.contributor_id) if row.contributor_id else str(row.id)
                    purpose = "thank_you"
                    rel_type = "contribution"
                    rel_id = str(row.contributor_id) if row.contributor_id else None

                pre_url = pre_rendered_map.get(str(row.id))
                stable_result: Dict[str, Any] = {}
                try:
                    if pre_url:
                        # Frontend already produced + uploaded a PNG; record
                        # it on the mapping so the public token URL serves
                        # the latest render, but keep the token-based URL
                        # as the canonical link we share with the recipient.
                        stable_result = generate_or_replace_card(
                            s,
                            recipient_type=rec_type,
                            recipient_id=rec_id,
                            card_purpose=purpose,
                            template_slug=tpl.slug if tpl else None,
                            event_id=str(ev.id),
                            related_entity_type=rel_type,
                            related_entity_id=rel_id,
                            pre_uploaded_url=pre_url,
                            public_host=f"https://{host}",
                        )
                        print(f"[event_card_dispatch] stable token={stable_result.get('token')} reusing pre-rendered upload sid={row.id}")
                    else:
                        svg, _ec, _tpl = _render_event_card_svg(
                            s, ev, dispatch_category,
                            contributor_name=row.recipient_name,
                            qr_payload=qr_payload,
                        )
                        png_bytes = _render_png_bytes(svg, tpl, width=1080)

                        def _uploader(stable_path: str, data: bytes, mime: str) -> Optional[str]:
                            if mime.startswith("image/png"):
                                return upload_card_png(stable_path, data)
                            return upload_card_svg(stable_path, data.decode("utf-8", errors="ignore"))

                        if png_bytes:
                            cache_key = f"{row.id}.png"
                            _storage.cache_put(cache_key, png_bytes)
                            stable_result = generate_or_replace_card(
                                s,
                                recipient_type=rec_type,
                                recipient_id=rec_id,
                                card_purpose=purpose,
                                template_slug=tpl.slug if tpl else None,
                                event_id=str(ev.id),
                                related_entity_type=rel_type,
                                related_entity_id=rel_id,
                                render_fn=lambda: (png_bytes, "image/png", "png"),
                                uploader=_uploader,
                                public_host=f"https://{host}",
                            )
                        else:
                            # PNG renderer unavailable; fall back to SVG via render-card edge function
                            svg_payload = svg.encode("utf-8")
                            stable_result = generate_or_replace_card(
                                s,
                                recipient_type=rec_type,
                                recipient_id=rec_id,
                                card_purpose=purpose,
                                template_slug=tpl.slug if tpl else None,
                                event_id=str(ev.id),
                                related_entity_type=rel_type,
                                related_entity_id=rel_id,
                                render_fn=lambda: (svg_payload, "image/svg+xml", "svg"),
                                uploader=_uploader,
                                public_host=f"https://{host}",
                            )

                except Exception as exc:
                    print(f"[pledge_card_dispatch] stable URL generation failed: {exc!r}")
                    stable_result = {}

                # Two URLs, two purposes:
                #   • whatsapp_image_url — MUST be a direct image (Meta fetches
                #     bytes; the /card/{token} frontend route returns HTML and
                #     fails with HTTP 404 on Meta's side).
                #   • text_card_url — friendly token URL we share over SMS or
                #     plain-text messages (humans tap it, the frontend resolves
                #     it to the rendered card view).
                # `rendered_card_url` on the row is used by the mobile/web
                # "Your Invitation QR Code" screens to <img src=…>, so it must
                # also be a direct image — store storage_url, fall back to the
                # backend resolver which returns PNG bytes, never the frontend
                # /card/{token} route.
                direct_image_url = (
                    stable_result.get("storage_url")
                    or (f"{api_base}/api/v1/cards/public/by-token/{stable_result['token']}.png"
                        if stable_result.get("token") else None)
                    or fallback_image_url
                )
                text_card_url = stable_result.get("public_url") or landing_url
                whatsapp_image_url = direct_image_url
                # Resolve (or lazily generate) the WhatsApp-safe JPEG sibling
                # so Meta does not reject the header with error 131053.
                # Falls back to the original PNG URL on any failure.
                wa_media_info = {}
                try:
                    from utils.whatsapp_media import ensure_whatsapp_media_for_png_url
                    wa_media_info = ensure_whatsapp_media_for_png_url(direct_image_url) or {}
                    if wa_media_info.get("url"):
                        whatsapp_image_url = wa_media_info["url"]
                except Exception as _wa_exc:  # noqa: BLE001
                    print(f"[event_card_dispatch] whatsapp media prepare failed: {_wa_exc!r}")
                image_url = whatsapp_image_url  # used by WhatsApp template + logs
                print(
                    f"[event_card_dispatch] media original_png={direct_image_url} "
                    f"whatsapp_url={whatsapp_image_url} "
                    f"wa_bytes={wa_media_info.get('size')} "
                    f"wa_dim={wa_media_info.get('width')}x{wa_media_info.get('height')} "
                    f"wa_reused={wa_media_info.get('reused')} "
                    f"wa_prepare_error={wa_media_info.get('error')!r}"
                )

                row.rendered_card_url = direct_image_url
                s.commit()

                channels = []
                phone = row.recipient_phone
                ok_wa = False
                wa_message_id = None
                wa_error = None
                wa_not_on_whatsapp = False
                if phone:
                    try:
                        from utils.whatsapp import _send_whatsapp_sync
                        from utils.whatsapp_availability import record_send_outcome
                        if is_guest_row:
                            # Approved Meta templates: invitation_card_sw / invitation_card_en
                            # Body placeholders required: {{1}} guest_name,
                            # {{2}} organizer_name, {{3}} event_name,
                            # {{4}} event_date (language-formatted),
                            # {{5}} venue, {{6}} organizer_phone.
                            # Resolve display name via the central helper:
                            # recognizable_event_owner_name → owner user → creator.
                            from utils.event_owner import get_event_owner_display_name
                            from utils.datetime_format import format_event_datetime
                            organizer_name = get_event_owner_display_name(ev, db=s)
                            # Organizer phone MUST be the phone of the
                            # user who CREATED the event (organizer_id),
                            # never the on-behalf-of event owner. This
                            # keeps replies routed to the actual operator.
                            organizer_phone = ""
                            try:
                                creator_uid = getattr(ev, "organizer_id", None)
                                if creator_uid:
                                    creator_user = s.query(User).filter(User.id == creator_uid).first()
                                    if creator_user:
                                        organizer_phone = (getattr(creator_user, "phone", None) or "").strip()
                            except Exception:
                                pass
                            wa_lang = "en" if lang == "en" else "sw"
                            # Combine separate ``start_date`` (date portion) and
                            # ``start_time`` (time-of-day) columns. Either field
                            # may be a ``date``/``datetime``/``time`` so we
                            # normalise defensively before formatting. Without
                            # this combine the body rendered "TBA" whenever the
                            # date column held only midnight while the real
                            # time-of-day lived on ``start_time``.
                            from datetime import datetime as _dt, date as _date, time as _time
                            _sd = getattr(ev, "start_date", None)
                            _st = getattr(ev, "start_time", None)
                            event_dt_value = None
                            if isinstance(_sd, _dt):
                                event_dt_value = _sd
                            elif isinstance(_sd, _date):
                                event_dt_value = _dt(_sd.year, _sd.month, _sd.day)
                            if event_dt_value is not None and _st is not None:
                                _tod = None
                                if isinstance(_st, _dt):
                                    _tod = _st.time()
                                elif isinstance(_st, _time):
                                    _tod = _st
                                if _tod is not None:
                                    event_dt_value = event_dt_value.replace(
                                        hour=_tod.hour, minute=_tod.minute,
                                        second=_tod.second, microsecond=0,
                                    )
                            if event_dt_value is None and isinstance(_st, _dt):
                                event_dt_value = _st
                            # ``start_time`` is captured in the organiser's
                            # local EAT clock (e.g. user picks 18:00 EAT and
                            # we store that exact wall time on the row). Tag
                            # the combined value with EAT so the formatter
                            # does not re-interpret it as UTC and shift +3h
                            # (which previously rendered 18:00 as 21:00/23:00).
                            if event_dt_value is not None and event_dt_value.tzinfo is None:
                                try:
                                    import pytz as _pytz
                                    event_dt_value = _pytz.timezone(
                                        "Africa/Nairobi"
                                    ).localize(event_dt_value)
                                except Exception:
                                    pass
                            formatted_event_date = format_event_datetime(
                                event_dt_value, lang=wa_lang
                            ) or "TBA"


                            venue_text = ""
                            try:
                                vc = getattr(ev, "venue_coordinate", None)
                                if vc and getattr(vc, "venue_name", None):
                                    venue_text = (vc.venue_name or "").strip()
                            except Exception:
                                pass
                            if not venue_text:
                                venue_text = (getattr(ev, "location", None) or "").strip()
                            wa_action = "invitation_card_message"
                            wa_params = {
                                "guest_name": row.recipient_name or "Guest",
                                # Never send the generic "the organizer" placeholder —
                                # the helper above guarantees a real name when one
                                # exists. Empty string is acceptable for Meta.
                                "organizer_name": (organizer_name or "").strip(),
                                "event_name": ev.name or "the event",
                                "event_date": formatted_event_date,
                                "venue": venue_text or "TBA",
                                "organizer_phone": organizer_phone or "—",
                                "image_url": image_url or "",
                                "lang": wa_lang,
                                # Powers the WhatsApp quick-reply RSVP buttons
                                # (confirm / maybe / decline). Shared with the
                                # /rsvp/{code} URL flow.
                                "rsvp_code": (row.recipient_qr_payload or "").strip() or "—",
                            }
                        else:
                            wa_action = "pledge_thank_you_card"
                            wa_params = {
                                "contributor_name": row.recipient_name or "Friend",
                                "event_name": ev.name or "the event",
                                "image_url": image_url or "",
                                "lang": "en" if lang == "en" else "sw",
                            }
                        wa_result = _send_whatsapp_sync(wa_action, phone, wa_params) or {}
                        ok_wa = bool(wa_result.get("ok"))
                        wa_message_id = wa_result.get("message_id")
                        wa_not_on_whatsapp = bool(wa_result.get("not_on_whatsapp"))
                        wa_error = None if ok_wa else (wa_result.get("error") or "send failed")
                        try:
                            if ok_wa and wa_message_id:
                                record_send_outcome(
                                    s, phone,
                                    message_id=str(wa_message_id),
                                    action=wa_action,
                                )
                            elif wa_not_on_whatsapp:
                                record_send_outcome(
                                    s, phone,
                                    not_on_whatsapp=True,
                                    error_code=str(wa_result.get("error_code") or "131026"),
                                    error_message=wa_error,
                                    action=wa_action,
                                )
                            elif not ok_wa:
                                record_send_outcome(
                                    s, phone,
                                    error_code=str(wa_result.get("error_code") or wa_result.get("status") or ""),
                                    error_message=wa_error,
                                    action=wa_action,
                                )
                        except Exception as exc:
                            print(f"[event_card_dispatch] whatsapp availability record skipped: {exc}")
                        if ok_wa:
                            channels.append("whatsapp")
                    except Exception as exc:
                        wa_error = f"exception: {exc}"
                ok_sms = False
                sms_error = None
                if phone and sms_ok:
                    try:
                        ok_sms = bool(sms_pledge_thank_you_card(
                            phone=phone,
                            contributor_name=row.recipient_name,
                            event_name=ev.name or "the event",
                            card_link=(stable_result.get("public_url") or landing_url),
                            lang=lang,
                        ))
                        if ok_sms:
                            channels.append("sms")
                        else:
                            sms_error = "sms send returned false"
                    except Exception as exc:
                        sms_error = f"exception: {exc}"

                if wa_message_id:
                    row.whatsapp_message_id = wa_message_id
                error_parts = []
                if wa_error:
                    error_parts.append(f"wa: {wa_error}")
                if wa_not_on_whatsapp:
                    error_parts.append("wa: not_on_whatsapp")
                if sms_error:
                    error_parts.append(f"sms: {sms_error}")
                row.error_message = " | ".join(error_parts) if error_parts else None
                row.delivery_channel = "+".join(channels) or "none"
                row.delivery_status = "sent" if (ok_wa or ok_sms) else "failed"
                row.sent_at = datetime.utcnow()
                s.commit()

                # Structured per-recipient delivery report for troubleshooting.
                phone_mask = (phone[:5] + "***" + phone[-3:]) if phone and len(phone) > 8 else (phone or "")
                print(
                    f"[pledge_card_dispatch_report] sid={row.id} event_id={ev.id} "
                    f"contributor_id={row.contributor_id} name={row.recipient_name!r} "
                    f"phone={phone_mask} status={row.delivery_status} channel={row.delivery_channel} "
                    f"wa_ok={ok_wa} wa_message_id={wa_message_id} wa_not_on_whatsapp={wa_not_on_whatsapp} "
                    f"wa_error={wa_error!r} sms_ok={ok_sms} sms_error={sms_error!r} image_url={image_url}"
                )
        except Exception as exc:
            try:
                for sid in dispatch_sent_card_ids:
                    row = s.query(SentEventCard).filter(SentEventCard.id == uuid.UUID(str(sid))).first()
                    if row and row.delivery_status == "pending":
                        row.delivery_status = "failed"
                        row.error_message = f"dispatch: {exc}"
                        row.sent_at = datetime.utcnow()
                s.commit()
            except Exception as update_exc:
                s.rollback()
                print(f"[event_cards] failed to mark dispatch errors: {update_exc!r}")
            print(f"[event_cards] background dispatch failed: {exc!r}")
        finally:
            s.close()

    if background_tasks is not None:
        background_tasks.add_task(
            _dispatch,
            str(dispatch_event_id),
            category,
            sent_card_ids,
            str(dispatch_sender_user_id),
            sid_to_pre_rendered,
        )
    else:
        _dispatch(str(dispatch_event_id), category, sent_card_ids, str(dispatch_sender_user_id), sid_to_pre_rendered)

    return standard_response(True, f"Queued {len(sent_card_ids)} thank-you cards.", {
        "queued": len(sent_card_ids),
        "sent_ids": [str(x) for x in sent_card_ids],
    })


@router.get("/events/{event_id}/cards/{category}/recipient-status")
def card_recipient_status(
    event_id: str,
    category: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Which recipients already have a prepared / sent card for this card
    CATEGORY. Powers the "Only those not prepared / not sent yet" picker
    pre-filter — scoped by category (not template id) so switching
    templates within the same category still hides people correctly,
    exactly mirroring the backend ``skip_existing`` dispatch filter."""
    event = _assert_event_manager(db, event_id, current_user)
    category = _validate_category(category)
    rows = (
        db.query(
            SentEventCard.guest_attendee_id,
            SentEventCard.contributor_id,
            SentEventCard.delivery_status,
        )
        .join(EventCard, SentEventCard.event_card_id == EventCard.id)
        .filter(
            SentEventCard.event_id == event.id,
            EventCard.category == category,
        )
        .all()
    )
    prepared: set = set()
    sent: set = set()
    for gid, cid, status in rows:
        rid = str(gid or cid or "")
        if not rid:
            continue
        st = str(status or "")
        if st == "prepared":
            prepared.add(rid)
        elif st in ("sent", "delivered", "read"):
            sent.add(rid)
    return standard_response(True, "OK", {
        "prepared_ids": sorted(prepared),
        "sent_ids": sorted(sent),
    })


# ──────────────────────────────────────────────
# Prepared Cards (status='prepared' rows on sent_event_cards)
# Three-tab Cards layout: Templates / Prepared / Sent.
# Preparing = create the per-recipient SentEventCard row without dispatching.
# Sending later flips the status and reuses the existing dispatch path.
# ──────────────────────────────────────────────


@router.get("/events/{event_id}/prepared-cards")
def list_prepared_cards(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _assert_event_manager(db, event_id, current_user)
    rows = (
        db.query(SentEventCard)
        .filter(
            SentEventCard.event_id == event.id,
            SentEventCard.delivery_status == "prepared",
        )
        .order_by(SentEventCard.created_at.desc())
        .all()
    )
    ec_ids = {r.event_card_id for r in rows if r.event_card_id}
    ecs = {
        ec.id: ec
        for ec in db.query(EventCard).filter(EventCard.id.in_(ec_ids)).all()
    } if ec_ids else {}
    tpl_ids = {ec.card_template_id for ec in ecs.values() if ec.card_template_id}
    tpls = {
        t.id: t
        for t in db.query(CardTemplate).filter(CardTemplate.id.in_(tpl_ids)).all()
    } if tpl_ids else {}

    items = []
    for r in rows:
        ec = ecs.get(r.event_card_id) if r.event_card_id else None
        tpl = tpls.get(ec.card_template_id) if ec and ec.card_template_id else None
        items.append({
            "sent_id": str(r.id),
            "recipient_type": "guest" if r.guest_attendee_id else "contributor",
            "recipient_id": str(r.guest_attendee_id or r.contributor_id or ""),
            "recipient_name": r.recipient_name,
            "recipient_phone": r.recipient_phone,
            "rendered_card_url": r.rendered_card_url,
            "category": ec.category if ec else None,
            "template_id": str(tpl.id) if tpl else None,
            "template_slug": tpl.slug if tpl else None,
            "template_name": tpl.name if tpl else None,
            "prepared_at": r.created_at.isoformat() if r.created_at else None,
        })
    return standard_response(True, "OK", {"prepared_cards": items})


@router.post("/events/{event_id}/prepared-cards/discard")
def discard_prepared_cards(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _assert_event_manager(db, event_id, current_user)
    raw_ids = body.get("sent_ids") or []
    if not isinstance(raw_ids, list) or not raw_ids:
        raise HTTPException(status_code=400, detail="sent_ids is required")
    try:
        uuids = [uuid.UUID(str(x)) for x in raw_ids]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid sent_id")
    rows = (
        db.query(SentEventCard)
        .filter(
            SentEventCard.event_id == event.id,
            SentEventCard.id.in_(uuids),
            SentEventCard.delivery_status == "prepared",
        )
        .all()
    )
    n = 0
    for r in rows:
        db.delete(r)
        n += 1
    db.commit()
    return standard_response(True, f"Discarded {n} prepared cards.", {"discarded": n})


@router.post("/events/{event_id}/prepared-cards/send")
def send_prepared_cards(
    event_id: str,
    body: dict = Body(...),
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Send a set of previously prepared cards.

    Reuses the existing dispatch path by deleting the prepared placeholder rows
    and re-invoking ``send_pledge_thank_you_cards`` per category — the
    pre-rendered URL recorded at prepare time (``rendered_card_url``) is
    forwarded as ``pre_rendered_images`` so we never re-render server-side.
    """
    event = _assert_event_manager(db, event_id, current_user)
    raw_ids = body.get("sent_ids") or []
    if not isinstance(raw_ids, list) or not raw_ids:
        raise HTTPException(status_code=400, detail="sent_ids is required")
    try:
        uuids = [uuid.UUID(str(x)) for x in raw_ids]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid sent_id")

    rows = (
        db.query(SentEventCard)
        .filter(
            SentEventCard.event_id == event.id,
            SentEventCard.id.in_(uuids),
            SentEventCard.delivery_status == "prepared",
        )
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No prepared cards selected.")

    ec_ids = {r.event_card_id for r in rows if r.event_card_id}
    ecs = {
        ec.id: ec
        for ec in db.query(EventCard).filter(EventCard.id.in_(ec_ids)).all()
    } if ec_ids else {}

    # bucket by (category, recipient_kind)
    buckets: Dict[tuple, Dict[str, Any]] = {}
    for r in rows:
        ec = ecs.get(r.event_card_id) if r.event_card_id else None
        if not ec:
            continue
        kind = "guest" if r.guest_attendee_id else "contributor"
        key = (ec.category, kind)
        b = buckets.setdefault(key, {"ids": [], "pre_rendered": {}})
        rec_id = str(r.guest_attendee_id if kind == "guest" else r.contributor_id)
        b["ids"].append(rec_id)
        if r.rendered_card_url:
            b["pre_rendered"][rec_id] = r.rendered_card_url

    # Drop the placeholder rows so the dispatch can mint fresh ones with
    # the proper QR / stable-token wiring.
    for r in rows:
        db.delete(r)
    db.commit()

    total_queued = 0
    for (cat, kind), b in buckets.items():
        inner_body: Dict[str, Any] = {"pre_rendered_images": b["pre_rendered"]}
        if kind == "guest":
            inner_body["guest_ids"] = b["ids"]
        else:
            inner_body["contributor_ids"] = b["ids"]
        try:
            resp = send_pledge_thank_you_cards(
                event_id=str(event.id),
                category=cat,
                body=inner_body,
                background_tasks=background_tasks,
                db=db,
                current_user=current_user,
            )
            data = (resp or {}).get("data") if isinstance(resp, dict) else None
            total_queued += int((data or {}).get("queued", 0))
        except Exception as exc:
            print(f"[prepared_cards_send] dispatch failed cat={cat} kind={kind}: {exc!r}")

    return standard_response(
        True,
        f"Sending {total_queued} prepared cards.",
        {"queued": total_queued},
    )



@router.post("/events/{event_id}/sent-cards/resend")
def resend_sent_cards(
    event_id: str,
    body: dict = Body(...),
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Resend cards that were already dispatched at least once.

    Reuses each row's existing ``rendered_card_url`` as ``pre_rendered_images``
    so we never re-render server-side — the recipient gets exactly the same
    card image they saw before, just delivered again."""
    event = _assert_event_manager(db, event_id, current_user)
    raw_ids = body.get("sent_ids") or []
    if not isinstance(raw_ids, list) or not raw_ids:
        raise HTTPException(status_code=400, detail="sent_ids is required")
    try:
        uuids = [uuid.UUID(str(x)) for x in raw_ids]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid sent_id")

    rows = (
        db.query(SentEventCard)
        .filter(
            SentEventCard.event_id == event.id,
            SentEventCard.id.in_(uuids),
        )
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No matching cards selected.")

    ec_ids = {r.event_card_id for r in rows if r.event_card_id}
    ecs = {
        ec.id: ec
        for ec in db.query(EventCard).filter(EventCard.id.in_(ec_ids)).all()
    } if ec_ids else {}

    buckets: Dict[tuple, Dict[str, Any]] = {}
    for r in rows:
        ec = ecs.get(r.event_card_id) if r.event_card_id else None
        if not ec:
            continue
        kind = "guest" if r.guest_attendee_id else "contributor"
        key = (ec.category, kind)
        b = buckets.setdefault(key, {"ids": [], "pre_rendered": {}})
        rec_id = str(r.guest_attendee_id if kind == "guest" else r.contributor_id)
        b["ids"].append(rec_id)
        if r.rendered_card_url:
            b["pre_rendered"][rec_id] = r.rendered_card_url

    total_queued = 0
    for (cat, kind), b in buckets.items():
        inner_body: Dict[str, Any] = {
            "pre_rendered_images": b["pre_rendered"],
            "mode": "fresh",
        }
        if kind == "guest":
            inner_body["guest_ids"] = b["ids"]
        else:
            inner_body["contributor_ids"] = b["ids"]
        try:
            resp = send_pledge_thank_you_cards(
                event_id=str(event.id),
                category=cat,
                body=inner_body,
                background_tasks=background_tasks,
                db=db,
                current_user=current_user,
            )
            data = (resp or {}).get("data") if isinstance(resp, dict) else None
            total_queued += int((data or {}).get("queued", 0))
        except Exception as exc:
            print(f"[sent_cards_resend] dispatch failed cat={cat} kind={kind}: {exc!r}")

    return standard_response(
        True,
        f"Resending {total_queued} card{'s' if total_queued != 1 else ''}.",
        {"queued": total_queued},
    )



# ──────────────────────────────────────────────
# Public (no-auth) endpoints
# ──────────────────────────────────────────────

@router.get("/cards/public/{sent_id}.png")
def public_card_png(sent_id: str, db: Session = Depends(get_db)):
    try:
        sid = uuid.UUID(sent_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid id")
    cache_key = f"{sid}.png"
    cached = _storage.cache_get(cache_key)
    if cached:
        return Response(content=cached, media_type="image/png")
    row = db.query(SentEventCard).filter(SentEventCard.id == sid).first()
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    ec = db.query(EventCard).filter(EventCard.id == row.event_card_id).first() if row.event_card_id else None
    tpl = None
    if not ec:
        # Active card for this event category
        ec = db.query(EventCard).filter(
            EventCard.event_id == row.event_id, EventCard.is_active.is_(True)
        ).first()
    if ec:
        tpl = db.query(CardTemplate).filter(CardTemplate.id == ec.card_template_id).first()
    if not ec or not tpl:
        raise HTTPException(status_code=404, detail="Card configuration missing")
    event = db.query(Event).filter(Event.id == row.event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    svg, _ec, _tpl = _render_event_card_svg(db, event, ec.category, contributor_name=row.recipient_name, qr_payload=row.recipient_qr_payload)
    png = _render_png_bytes(svg, tpl, width=1080)
    if not png:
        raise HTTPException(status_code=503, detail="PNG renderer unavailable")
    _storage.cache_put(cache_key, png)
    return Response(content=png, media_type="image/png")


@router.get("/cards/public/{sent_id}.svg")
def public_card_svg(sent_id: str, db: Session = Depends(get_db)):
    try:
        sid = uuid.UUID(sent_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid id")
    row = db.query(SentEventCard).filter(SentEventCard.id == sid).first()
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    ec = db.query(EventCard).filter(EventCard.id == row.event_card_id).first() if row.event_card_id else None
    if not ec:
        ec = db.query(EventCard).filter(
            EventCard.event_id == row.event_id, EventCard.is_active.is_(True)
        ).first()
    if not ec:
        raise HTTPException(status_code=404, detail="Card configuration missing")
    event = db.query(Event).filter(Event.id == row.event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    svg, _ec, _tpl = _render_event_card_svg(db, event, ec.category, contributor_name=row.recipient_name, qr_payload=row.recipient_qr_payload)
    return Response(content=svg, media_type="image/svg+xml")


@router.get("/cards/public/{sent_id}", response_class=HTMLResponse)
def public_card_landing(sent_id: str, db: Session = Depends(get_db)):
    try:
        sid = uuid.UUID(sent_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid id")
    row = db.query(SentEventCard).filter(SentEventCard.id == sid).first()
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    img_url = f"/api/v1/cards/public/{sent_id}.png"
    deep_link = f"nuru://cards/{sent_id}"
    html = f"""<!doctype html>
<html lang=\"en\"><head><meta charset=\"utf-8\" />
<title>Thank you, {row.recipient_name}</title>
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
<meta property=\"og:image\" content=\"{img_url}\" />
<style>
 body{{margin:0;background:#1a1a1a;font-family:-apple-system,BlinkMacSystemFont,Inter,Arial,sans-serif;color:#fff;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px;gap:24px}}
 img{{max-width:min(560px,92vw);width:100%;border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,.5)}}
 a.btn{{display:inline-block;padding:14px 22px;border-radius:999px;background:#C98B28;color:#18251C;font-weight:600;text-decoration:none}}
 p{{opacity:.7;margin:0}}
</style></head>
<body>
 <img src=\"{img_url}\" alt=\"Thank you card for {row.recipient_name}\" />
 <a class=\"btn\" href=\"{deep_link}\">Open in Nuru app</a>
 <p>Plan Smarter. Celebrate Better.</p>
</body></html>"""
    return HTMLResponse(content=html)


# ──────────────────────────────────────────────
# Stable token-based public resolver
# (see backend/app/docs/card_url_mappings.md)
# ──────────────────────────────────────────────

from fastapi.responses import RedirectResponse  # noqa: E402
from models.card_url_mapping import CardUrlMapping  # noqa: E402

_TOKEN_RE = re.compile(r"^[A-Za-z0-9_\-]{8,64}$")


def _resolve_token(db: Session, token: str) -> CardUrlMapping:
    if not token or not _TOKEN_RE.match(token):
        raise HTTPException(status_code=400, detail="Invalid token")
    row = db.query(CardUrlMapping).filter(CardUrlMapping.token == token).first()
    if not row:
        raise HTTPException(status_code=404, detail="Card not found")
    return row


@router.get("/cards/public/by-token/{token}.png")
def public_card_by_token_png(token: str, db: Session = Depends(get_db)):
    row = _resolve_token(db, token)
    if row.storage_url:
        return RedirectResponse(row.storage_url, status_code=302)
    # Fall back to the per-sent-id render path if we have nothing cached yet.
    cache_key = f"token-{row.token}.png"
    cached = _storage.cache_get(cache_key)
    if cached:
        return Response(content=cached, media_type="image/png")
    raise HTTPException(status_code=404, detail="Card has not been rendered yet")


@router.get("/cards/public/by-token/{token}.svg")
def public_card_by_token_svg(token: str, db: Session = Depends(get_db)):
    row = _resolve_token(db, token)
    if row.storage_url:
        return RedirectResponse(row.storage_url, status_code=302)
    raise HTTPException(status_code=404, detail="Card has not been rendered yet")


@router.get("/cards/public/by-token/{token}", response_class=HTMLResponse)
def public_card_by_token_landing(token: str, db: Session = Depends(get_db)):
    row = _resolve_token(db, token)
    img_url = row.storage_url or f"/api/v1/cards/public/by-token/{token}.png"
    deep_link = f"nuru://card/{token}"
    html = f"""<!doctype html>
<html lang=\"en\"><head><meta charset=\"utf-8\" />
<title>Your Nuru card</title>
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
<meta property=\"og:image\" content=\"{img_url}\" />
<style>
 body{{margin:0;background:#1a1a1a;font-family:-apple-system,BlinkMacSystemFont,Inter,Arial,sans-serif;color:#fff;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px;gap:24px}}
 img{{max-width:min(560px,92vw);width:100%;border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,.5)}}
 a.btn{{display:inline-block;padding:14px 22px;border-radius:999px;background:#C98B28;color:#18251C;font-weight:600;text-decoration:none}}
 p{{opacity:.7;margin:0}}
</style></head>
<body>
 <img src=\"{img_url}\" alt=\"Your Nuru card\" />
 <a class=\"btn\" href=\"{deep_link}\">Open in Nuru app</a>
 <p>Plan Smarter. Celebrate Better.</p>
</body></html>"""
    return HTMLResponse(content=html)


# ──────────────────────────────────────────────
# Sent Cards browsing + bulk download (read-only, reuses existing
# rendered_card_url stored at send time; never regenerates new storage
# files. Streams ad-hoc ZIP/PDF exports back to the organiser.)
# ──────────────────────────────────────────────

_SAFE_FNAME_RE = re.compile(r"[^A-Za-z0-9._-]+")


def _safe_filename_segment(value: str, fallback: str = "card", max_len: int = 60) -> str:
    s = (value or "").strip()
    if not s:
        return fallback
    s = _SAFE_FNAME_RE.sub("-", s).strip("-_.")
    if not s:
        return fallback
    return s[:max_len]


def _derive_whatsapp_status(row: SentEventCard) -> str:
    """Best-effort WhatsApp availability label using existing send records."""
    if row.whatsapp_message_id:
        return "on_whatsapp"
    err = (row.error_message or "").lower()
    if "not_on_whatsapp" in err:
        return "not_on_whatsapp"
    ch = (row.delivery_channel or "").lower()
    if "whatsapp" in ch:
        return "on_whatsapp"
    return "unknown"


def _get_sent_card_png_bytes(db: Session, row: SentEventCard) -> Optional[bytes]:
    """Reuse the already-generated card. Tries (1) on-disk cache, (2) the
    saved rendered_card_url, (3) on-the-fly server render as last resort.
    Never writes to persistent storage."""
    cache_key = f"{row.id}.png"
    cached = _storage.cache_get(cache_key)
    if cached:
        return cached
    url = row.rendered_card_url
    if url and url.startswith(("http://", "https://")):
        try:
            import httpx
            with httpx.Client(timeout=20.0, follow_redirects=True) as client:
                resp = client.get(url)
                if resp.status_code == 200 and resp.content:
                    return resp.content
        except Exception as exc:
            print(f"[sent_cards_download] fetch failed for sid={row.id}: {exc!r}")
    try:
        ec = (
            db.query(EventCard).filter(EventCard.id == row.event_card_id).first()
            if row.event_card_id
            else None
        )
        if not ec:
            ec = (
                db.query(EventCard)
                .filter(EventCard.event_id == row.event_id, EventCard.is_active.is_(True))
                .first()
            )
        if not ec:
            return None
        tpl = db.query(CardTemplate).filter(CardTemplate.id == ec.card_template_id).first()
        event = db.query(Event).filter(Event.id == row.event_id).first()
        if not tpl or not event:
            return None
        svg, _ec, _tpl = _render_event_card_svg(
            db, event, ec.category,
            contributor_name=row.recipient_name,
            qr_payload=row.recipient_qr_payload,
        )
        png = _render_png_bytes(svg, tpl, width=1080)
        if png:
            _storage.cache_put(cache_key, png)
        return png
    except Exception as exc:
        print(f"[sent_cards_download] render fallback failed for sid={row.id}: {exc!r}")
        return None


@router.get("/events/{event_id}/sent-cards/templates")
def list_sent_card_templates(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Unique card templates that have at least one delivery record for this
    event, with recipient counts and the most-recent send timestamp."""
    event = _assert_event_manager(db, event_id, current_user)
    rows = (
        db.query(SentEventCard, EventCard, CardTemplate)
        .join(EventCard, SentEventCard.event_card_id == EventCard.id)
        .join(CardTemplate, EventCard.card_template_id == CardTemplate.id)
        .filter(
            SentEventCard.event_id == event.id,
            # Hide the "prepared but not yet sent" rows — they live on the
            # Prepared Cards tab. Sent Cards only shows actual deliveries.
            SentEventCard.delivery_status != "prepared",
        )
        .all()
    )
    by_tpl: Dict[str, Dict[str, Any]] = {}
    recipients_seen: Dict[str, set] = {}
    for s, ec, t in rows:
        key = str(t.id)
        entry = by_tpl.get(key)
        if not entry:
            entry = {
                "template_id": str(t.id),
                "event_card_id": str(ec.id),
                "slug": t.slug,
                "name": t.name,
                "category": t.category,
                "thumbnail_url": (
                    f"/api/v1/cards/templates/{t.slug}/asset/{(t.metadata_json or {}).get('thumbnail_file')}"
                    if (t.metadata_json or {}).get("thumbnail_file") else None
                ),
                "recipient_count": 0,
                "total_sends": 0,
                "last_sent_at": None,
            }
            by_tpl[key] = entry
            recipients_seen[key] = set()
        entry["total_sends"] += 1
        rkey = str(s.contributor_id or s.guest_attendee_id or s.recipient_phone or s.id)
        recipients_seen[key].add(rkey)
        ts = s.sent_at or s.created_at
        if ts:
            iso = ts.isoformat()
            if not entry["last_sent_at"] or iso > entry["last_sent_at"]:
                entry["last_sent_at"] = iso
    out = []
    for k, entry in by_tpl.items():
        entry["recipient_count"] = len(recipients_seen.get(k, set()))
        out.append(entry)
    out.sort(key=lambda x: x.get("last_sent_at") or "", reverse=True)
    return standard_response(True, "OK", {"templates": out})


@router.get("/events/{event_id}/sent-cards/templates/{template_id}/recipients")
def list_sent_card_recipients(
    event_id: str,
    template_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Latest send per recipient for a given template."""
    event = _assert_event_manager(db, event_id, current_user)
    try:
        tpl_uuid = uuid.UUID(template_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid template id")
    ec_ids = [
        ec.id for ec in db.query(EventCard).filter(
            EventCard.event_id == event.id,
            EventCard.card_template_id == tpl_uuid,
        ).all()
    ]
    if not ec_ids:
        return standard_response(True, "OK", {"recipients": []})
    rows = (
        db.query(SentEventCard)
        .filter(
            SentEventCard.event_id == event.id,
            SentEventCard.event_card_id.in_(ec_ids),
            SentEventCard.delivery_status != "prepared",
        )
        .order_by(SentEventCard.sent_at.desc().nullslast(), SentEventCard.created_at.desc())
        .all()
    )
    latest: Dict[str, SentEventCard] = {}
    for r in rows:
        key = str(r.contributor_id or r.guest_attendee_id or r.recipient_phone or r.id)
        if key in latest:
            continue
        latest[key] = r
    api_base = _public_api_base(os.getenv("API_PUBLIC_HOST", "nuru.tz"))
    out = []
    for r in latest.values():
        url = r.rendered_card_url or f"{api_base}/api/v1/cards/public/{r.id}.png"
        ts = r.sent_at or r.created_at
        out.append({
            "sent_id": str(r.id),
            # Expose the originating recipient ids so the "Only those not
            # sent yet" pre-filter on the send picker can drop people who
            # already received a card without an extra lookup.
            "contributor_id": str(r.contributor_id) if r.contributor_id else None,
            "guest_attendee_id": str(r.guest_attendee_id) if r.guest_attendee_id else None,
            "recipient_name": r.recipient_name,
            "recipient_phone": r.recipient_phone,
            "rendered_card_url": url,
            "sent_at": ts.isoformat() if ts else None,
            "delivery_status": r.delivery_status,
            "delivery_channel": r.delivery_channel,
            "whatsapp_status": _derive_whatsapp_status(r),
        })
    out.sort(key=lambda x: (x.get("recipient_name") or "").lower())
    return standard_response(True, "OK", {"recipients": out})


@router.post("/events/{event_id}/sent-cards/download")
def download_sent_cards(
    event_id: str,
    body: dict = Body(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Bundle the most recent generated card for each selected recipient
    into either a ZIP of PNGs or a single PDF. The existing rendered_card_url
    is reused — no new card files are persisted."""
    event = _assert_event_manager(db, event_id, current_user)
    raw_ids = body.get("sent_ids") or []
    fmt = (body.get("format") or "images").lower()
    if fmt not in ("images", "pdf"):
        raise HTTPException(status_code=400, detail="format must be 'images' or 'pdf'")
    if not isinstance(raw_ids, list) or not raw_ids:
        raise HTTPException(status_code=400, detail="sent_ids is required")
    try:
        uuids = [uuid.UUID(str(x)) for x in raw_ids]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid sent_id in list")
    rows = (
        db.query(SentEventCard)
        .filter(SentEventCard.event_id == event.id, SentEventCard.id.in_(uuids))
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No matching sent cards on this event.")

    ec_ids = {r.event_card_id for r in rows if r.event_card_id}
    ec_map: Dict[Any, EventCard] = {}
    if ec_ids:
        for ec in db.query(EventCard).filter(EventCard.id.in_(ec_ids)).all():
            ec_map[ec.id] = ec
    tpl_map: Dict[Any, CardTemplate] = {}
    tpl_ids = {ec.card_template_id for ec in ec_map.values()}
    if tpl_ids:
        for t in db.query(CardTemplate).filter(CardTemplate.id.in_(tpl_ids)).all():
            tpl_map[t.id] = t

    event_seg = _safe_filename_segment(event.name or "event", fallback="event")

    items: List[Dict[str, Any]] = []
    for r in rows:
        png = _get_sent_card_png_bytes(db, r)
        if not png:
            continue
        ec = ec_map.get(r.event_card_id) if r.event_card_id else None
        tpl = tpl_map.get(ec.card_template_id) if ec else None
        tpl_name = tpl.name if tpl else "card"
        name_parts = [
            event_seg,
            _safe_filename_segment(tpl_name, fallback="card"),
            _safe_filename_segment(r.recipient_name or "guest", fallback="guest"),
        ]
        if r.recipient_phone:
            name_parts.append(_safe_filename_segment(r.recipient_phone, fallback=""))
        fname = "_".join([p for p in name_parts if p]) + ".png"
        items.append({"filename": fname, "png": png})

    if not items:
        raise HTTPException(status_code=404, detail="No generated cards are available for download yet.")

    import io, time
    timestamp = time.strftime("%Y%m%d-%H%M%S")

    def _png_to_pdf_bytes(png_bytes: bytes) -> bytes:
        from PIL import Image
        from reportlab.pdfgen import canvas
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.utils import ImageReader
        page_w, page_h = A4
        margin = 24.0
        avail_w = page_w - 2 * margin
        avail_h = page_h - 2 * margin
        img = Image.open(io.BytesIO(png_bytes))
        iw, ih = img.size
        scale = min(avail_w / max(iw, 1), avail_h / max(ih, 1))
        w = iw * scale
        h = ih * scale
        x = (page_w - w) / 2
        y = (page_h - h) / 2
        pbuf = io.BytesIO()
        c = canvas.Canvas(pbuf, pagesize=A4)
        c.drawImage(
            ImageReader(io.BytesIO(png_bytes)),
            x, y, width=w, height=h,
            preserveAspectRatio=True, mask='auto',
        )
        c.showPage()
        c.save()
        return pbuf.getvalue()

    if fmt == "images":
        # Single image → return raw PNG, no zip (fast).
        if len(items) == 1:
            item = items[0]
            return Response(
                content=item["png"],
                media_type="image/png",
                headers={"Content-Disposition": f'attachment; filename="{item["filename"]}"'},
            )
        import zipfile
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            seen_names: Dict[str, int] = {}
            for item in items:
                name = item["filename"]
                if name in seen_names:
                    seen_names[name] += 1
                    base, ext = os.path.splitext(name)
                    name = f"{base}-{seen_names[name]}{ext}"
                else:
                    seen_names[name] = 1
                zf.writestr(name, item["png"])
        zname = f"invitation_cards_{timestamp}.zip"
        return Response(
            content=buf.getvalue(),
            media_type="application/zip",
            headers={"Content-Disposition": f'attachment; filename="{zname}"'},
        )

    # PDF
    if len(items) == 1:
        item = items[0]
        pdf = _png_to_pdf_bytes(item["png"])
        base = os.path.splitext(item["filename"])[0]
        return Response(
            content=pdf,
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{base}.pdf"'},
        )
    # Multiple PDFs → zip of per-recipient PDFs (names = contributor).
    import zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        seen_names: Dict[str, int] = {}
        for item in items:
            try:
                pdf = _png_to_pdf_bytes(item["png"])
            except Exception as exc:
                print(f"[sent_cards_download] pdf gen failed: {exc!r}")
                continue
            base = os.path.splitext(item["filename"])[0]
            name = f"{base}.pdf"
            if name in seen_names:
                seen_names[name] += 1
                name = f"{base}-{seen_names[name]}.pdf"
            else:
                seen_names[name] = 1
            zf.writestr(name, pdf)
    zname = f"invitation_cards_{timestamp}.zip"
    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{zname}"'},
    )
