# WhatsApp notification helpers
# =============================
# Source of truth for template names + placeholder contracts:
#   backend/app/docs/whatsapp_templates_catalogue.md
#
# Every helper here passes the catalogue-aligned ``action`` name to the
# ``whatsapp-send`` edge function, plus an explicit ``lang`` ("sw"/"en")
# so the edge function can route to the correct ``_sw`` / ``_en`` Meta
# template. Money values are pre-formatted into a single combined string
# (e.g. ``"TZS 10,000"``) — Meta forbids placeholder reuse so each money
# slot is exactly one parameter.

import os
import requests

WHATSAPP_SIGNATURE = "\n-- Nuru: Keep your event together"

SUPABASE_URL = (os.getenv("EDGE_FUNCTION_URL", "") or os.getenv("SUPABASE_URL", "") or os.getenv("VITE_SUPABASE_URL", "")).rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "") or os.getenv("SUPABASE_PUBLISHABLE_KEY", "") or os.getenv("VITE_SUPABASE_PUBLISHABLE_KEY", "")
CURRENT_FUNCTIONS_URL = "https://lmfprculxhspqxppscbn.supabase.co"
WHATSAPP_SEND_URL = f"{SUPABASE_URL}/functions/v1/whatsapp-send" if SUPABASE_URL else ""


def _normalize_phone(phone: str) -> str:
    if not phone:
        return ""
    # Strip whitespace, +, -, brackets, dots — keep digits only after a possible leading +
    raw = str(phone).strip()
    for ch in (" ", "+", "-", "(", ")", ".", "\u00a0"):
        raw = raw.replace(ch, "")
    if not raw.isdigit():
        # keep digits only
        raw = "".join(c for c in raw if c.isdigit())
    if not raw:
        return ""
    # Tanzania local formats: 07XXXXXXXX / 06XXXXXXXX → 2557.../2556...
    if raw.startswith("0") and len(raw) == 10:
        return "255" + raw[1:]
    if raw.startswith("255"):
        return raw
    return raw


def _mask_phone(phone: str) -> str:
    """Safe log representation: e.g. 2557...0805 (full intl prefix + last 4)."""
    if not phone:
        return "?"
    p = str(phone)
    if len(p) <= 4:
        return "*" * len(p)
    return f"{p[:4]}...{p[-4:]}"


def _money(amount, currency: str = "TZS") -> str:
    """Pre-format a money value into one combined string for Meta."""
    cur = (currency or "TZS").upper()
    try:
        return f"{cur} {float(amount or 0):,.0f}"
    except Exception:
        return f"{cur} 0"


def _lang(value) -> str:
    return "en" if str(value or "sw").lower() == "en" else "sw"


def _send_whatsapp_sync(action: str, phone: str, params: dict, log_id: str | None = None, meta: dict | None = None):
    """Synchronous transport — only call from Celery workers.

    Returns a dict ``{ok, message_id, status, not_on_whatsapp, error,
    error_code, error_title, error_details, fbtrace_id}``. ``meta`` is
    forwarded to ``log_attempt`` when this function has to create the
    log row itself (no ``log_id`` supplied).
    """
    if log_id is None:
        try:
            from utils.wa_logging import log_attempt
            log_id = log_attempt(action, phone, params or {}, meta=meta)
        except Exception as _e:  # noqa: BLE001
            log_id = None
            print(f"[wa_log] attempt log skipped: {_e}")

    def _finish(result: dict):
        try:
            from utils.wa_logging import update_from_send_result
            update_from_send_result(log_id, result)
        except Exception as _e:  # noqa: BLE001
            print(f"[wa_log] update failed: {_e}")
        return result

    if not phone or not SUPABASE_ANON_KEY:
        return _finish({"ok": False, "error": "missing phone or anon key"})
    international_phone = _normalize_phone(phone)
    if not international_phone:
        return _finish({"ok": False, "error": "phone normalization failed"})
    phone_tail = _mask_phone(international_phone)


    # ── WhatsApp-safe media normalization ────────────────────────────────
    # Meta rejects large/alpha PNG headers with error 131053. For every
    # outgoing template that carries an image URL (image_url / media_url /
    # header_image), swap a .png URL for its .wa.jpg sibling — generated
    # on-demand if it does not already exist. This single guard covers
    # first sends, prepared-cards send, send-all, sent-cards resend AND
    # the WhatsApp Logs resend endpoint (which replays params verbatim).
    try:
        if isinstance(params, dict):
            from utils.whatsapp_media import ensure_whatsapp_media_for_png_url
            params = dict(params)  # don't mutate the caller's dict
            for k in ("image_url", "media_url", "header_image"):
                v = params.get(k)
                if not isinstance(v, str):
                    continue
                vl = v.lower().partition("?")[0]
                if not (vl.endswith(".png") or vl.endswith(".jpg") or vl.endswith(".jpeg")):
                    continue
                info = ensure_whatsapp_media_for_png_url(v) or {}
                safe = info.get("url")
                if safe and safe != v:
                    print(
                        f"[WhatsApp] media-safe swap action={action} key={k} "
                        f"src={v} jpg={safe} reused={info.get('reused')} "
                        f"size={info.get('size')} err={info.get('error')!r}"
                    )
                    params[k] = safe

    except Exception as _media_exc:  # noqa: BLE001
        print(f"[WhatsApp] media-safe swap skipped: {_media_exc}")

    # ── WhatsApp template-param sanitization ─────────────────────────────
    # Meta rejects any template body/header variable that contains
    # new-line, tab, or more than 4 consecutive spaces (error 132000 /
    # 132018: "Param text cannot have new-line/tab characters or more
    # than 4 consecutive spaces"). Imported data (payment_instructions,
    # organiser notes, etc.) often carries "\r\n". Strip it here so the
    # guarantee applies to every action and every call site.
    try:
        if isinstance(params, dict):
            MEDIA_KEYS = {"image_url", "media_url", "header_image", "document_url", "video_url"}
            def _clean_wa_param(v):
                if not isinstance(v, str):
                    return v
                s = v.replace("\r\n", " ").replace("\r", " ").replace("\n", " ").replace("\t", " ")
                # Collapse runs of 5+ spaces down to 4 (Meta's hard limit).
                import re as _re
                s = _re.sub(r" {5,}", "    ", s)
                return s.strip()
            for k, v in list(params.items()):
                if k in MEDIA_KEYS:
                    continue
                params[k] = _clean_wa_param(v)
    except Exception as _san_exc:  # noqa: BLE001
        print(f"[WhatsApp] param sanitize skipped: {_san_exc}")

    urls = [WHATSAPP_SEND_URL] if WHATSAPP_SEND_URL else []
    fallback_url = f"{CURRENT_FUNCTIONS_URL}/functions/v1/whatsapp-send"
    if fallback_url not in urls:
        urls.append(fallback_url)
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "apikey": SUPABASE_ANON_KEY,
    }
    payload = {"action": action, "phone": international_phone, "params": params}
    param_keys = sorted(list((params or {}).keys()))
    print(f"[WhatsApp] →edge action={action} phone_tail={phone_tail} param_keys={param_keys}")
    try:
        for index, url in enumerate(urls):
            resp = requests.post(url, json=payload, headers=headers, timeout=15)
            body = resp.text[:500]
            if not resp.ok:
                is_stale_local_function = resp.status_code == 400 and "Unknown action" in body and index < len(urls) - 1
                if is_stale_local_function:
                    print(f"[WhatsApp] local function missing action={action}; retrying deployed function")
                    continue
                print(f"[WhatsApp] ←edge HTTP {resp.status_code} action={action} phone_tail={phone_tail} body={body}")
                return _finish({"ok": False, "status": resp.status_code, "error": body})
            try:
                data = resp.json()
            except Exception:
                data = {}
            success = data.get("success")
            sent = data.get("sent")
            message_id = data.get("message_id")
            not_on_wa = bool(data.get("not_on_whatsapp"))
            print(
                f"[WhatsApp] ←edge HTTP {resp.status_code} action={action} phone_tail={phone_tail} "
                f"success={success} sent={sent} message_id={message_id} not_on_whatsapp={not_on_wa} body={body}"
            )
            if success is False or sent is False or not message_id:
                return _finish({
                    "ok": False,
                    "status": resp.status_code,
                    "message_id": message_id,
                    "not_on_whatsapp": not_on_wa,
                    "error_code": data.get("error_code"),
                    "error_title": data.get("error_title"),
                    "error_details": data.get("error_details"),
                    "fbtrace_id": data.get("fbtrace_id"),
                    "error": body,
                })

            try:
                from core.database import SessionLocal
                from api.routes.whatsapp_admin import _store_incoming
                db = SessionLocal()
                try:
                    summary = _whatsapp_admin_summary(action, params or {})
                    image_url = (params or {}).get("image_url") or (params or {}).get("media_url") or (params or {}).get("header_image")
                    _store_incoming(
                        db,
                        phone=international_phone,
                        content=summary,
                        wa_message_id=str(message_id),
                        contact_name=str((params or {}).get("guest_name") or (params or {}).get("contributor_name") or (params or {}).get("name") or ""),
                        direction="outbound",
                        media_url=str(image_url) if image_url else None,
                        media_type="image" if image_url else None,
                    )
                finally:
                    db.close()
            except Exception as mirror_exc:  # noqa: BLE001
                print(f"[WhatsApp] admin mirror skipped action={action} phone_tail={phone_tail}: {mirror_exc}")
            return _finish({"ok": True, "status": resp.status_code, "message_id": message_id})
        return _finish({"ok": False, "error": "no edge URL responded"})
    except Exception as e:
        print(f"[WhatsApp] exception action={action} phone_tail={phone_tail}: {e}")
        return _finish({"ok": False, "error": str(e)})


def _send_whatsapp(action: str, phone: str, params: dict, log_id: str | None = None, meta: dict | None = None):
    """Enqueue via Celery in prod, fall back to synchronous in dev.

    Always creates a ``wa_message_logs`` row up-front (when one isn't
    supplied) so no attempt is silent — even if Celery later loses the
    task. The log id is passed through to the worker so the same row is
    updated after Meta responds.

    ``meta`` (optional) carries per-recipient logging metadata:
      ``event_id``, ``event_name``, ``recipient_type``, ``recipient_id``,
      ``recipient_name``, ``message_purpose``, ``source_module``,
      ``related_entity_type``, ``related_entity_id``.
    """
    if not phone:
        return False
    if log_id is None:
        try:
            from utils.wa_logging import log_attempt
            log_id = log_attempt(action, phone, params or {}, meta=meta)
        except Exception as _e:  # noqa: BLE001
            log_id = None
            print(f"[wa_log] enqueue log skipped: {_e}")
    try:
        from core.celery_app import CELERY_ENABLED
    except Exception:
        CELERY_ENABLED = False
    if CELERY_ENABLED:
        try:
            from tasks.whatsapp_dispatch import send_action
            send_action.delay(action, phone, params or {}, log_id)
            return True
        except Exception as e:
            print(f"[WhatsApp] enqueue failed, sending inline: {e}")
    result = _send_whatsapp_sync(action, phone, params or {}, log_id=log_id, meta=meta)
    return bool(result.get("ok")) if isinstance(result, dict) else bool(result)



def _whatsapp_admin_summary(action: str, params: dict) -> str:
    if params.get("message"):
        return str(params.get("message"))[:1000]
    labels = {
        "contribution_recorded_with_balance": "Contribution recorded",
        "contribution_recorded": "Contribution recorded",
        "contribution_recorded_pledge_complete": "Contribution completed",
        "invitation_card_message": "Invitation card sent",
        "send_invitation_card": "Invitation card sent",
        "pledge_thank_you_card": "Thank-you card sent",
        "guest_invitation": "Guest invitation sent",
        "send_invitation_text": "Invitation message sent",
    }
    label = labels.get(action) or action.replace("_", " ").strip().title() or "WhatsApp message"
    parts = [label]
    name = params.get("guest_name") or params.get("contributor_name") or params.get("recipient_name") or params.get("name")
    event_name = params.get("event_name")
    amount = params.get("amount_text") or params.get("amount")
    if name:
        parts.append(str(name))
    if event_name:
        parts.append(str(event_name))
    if amount:
        parts.append(str(amount))
    return " | ".join(parts)[:1000]


def _send_whatsapp_text(phone: str, message: str):
    _send_whatsapp("text", phone, {"message": message})


# ──────────────────────────────────────────────
# #1/2 — guest_invitation
# ──────────────────────────────────────────────
def wa_guest_invited(
    phone: str,
    guest_name: str,
    event_name: str,
    event_date: str = "",
    organizer_name: str = "",
    rsvp_code: str = "",
    event_venue: str = "",
    lang: str = "sw",
    meta: dict | None = None,):
    _send_whatsapp("guest_invitation", phone, {
        "guest_name": guest_name,
        "organizer_name": organizer_name,
        "event_name": event_name,
        "event_date": event_date,
        "event_venue": event_venue or "TBA",
        "rsvp_code": rsvp_code,
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #3/4 — committee_invite
# ──────────────────────────────────────────────
def wa_committee_invite(
    phone: str,
    member_name: str,
    organizer_name: str,
    role: str,
    event_name: str,
    custom_message: str = "",
    lang: str = "sw",
    meta: dict | None = None,):
    _send_whatsapp("committee_invite", phone, {
        "member_name": member_name,
        "organizer_name": organizer_name,
        "role": role,
        "event_name": event_name,
        "custom_message": custom_message or "",
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #5/6 — welcome_registered_by (URL button)
# ──────────────────────────────────────────────
def wa_welcome_registered_by(
    phone: str,
    *,
    new_user_name: str,
    registered_by_name: str,
    setup_token: str,
    lang: str = "sw",
):
    return _send_whatsapp("welcome_registered_by", phone, {
        "new_user_name": new_user_name,
        "registered_by_name": registered_by_name,
        "setup_token": setup_token,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #7/8 — meeting_invitation (URL button)
# ──────────────────────────────────────────────
def wa_meeting_invitation(
    phone: str,
    event_name: str,
    meeting_title: str,
    scheduled_time: str,
    meeting_link: str = "",
    meeting_redirect_token: str = "",
    lang: str = "sw",
    meta: dict | None = None,):
    return _send_whatsapp("meeting_invitation", phone, {
        "event_name": event_name,
        "meeting_title": meeting_title,
        "scheduled_time": scheduled_time,
        "meeting_redirect_token": meeting_redirect_token or "",
        "meeting_link": meeting_link,
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #9/10 + #11/12 — contribution_recorded (with balance OR pledge complete)
# ──────────────────────────────────────────────
def wa_contribution_recorded(
    phone: str,
    contributor_name: str,
    event_title: str,
    amount: float,
    target: float,
    total_paid: float,
    currency: str = "TZS",
    organizer_phone: str = "",
    recorder_name: str = "",
    lang: str = "sw",
    meta: dict | None = None,):
    balance = max(0, (target or 0) - (total_paid or 0))
    pledge_complete = bool(target and target > 0 and balance <= 0)

    base = {
        "contributor_name": contributor_name,
        "amount_text": _money(amount, currency),
        "recorder_name": recorder_name or ("Mratibu" if _lang(lang) == "sw" else "The organizer"),
        "event_name": event_title,
        "organizer_phone": organizer_phone or "Nuru",
        "lang": _lang(lang),
    }

    if pledge_complete:
        base["target_text"] = _money(target, currency)
        _send_whatsapp("contribution_recorded_pledge_complete", phone, base)
    else:
        base["total_paid_text"] = _money(total_paid, currency)
        base["balance_text"] = _money(balance, currency) if target and target > 0 else "N/A"
        _send_whatsapp("contribution_recorded_with_balance", phone, base)


# ──────────────────────────────────────────────
# #13/14 — contribution_target_set
# ──────────────────────────────────────────────
def wa_contribution_target_set(
    phone: str,
    contributor_name: str,
    event_title: str,
    target: float,
    total_paid: float = 0,
    currency: str = "TZS",
    organizer_phone: str = "",
    lang: str = "sw",
    payment_instructions: str | None = None,
    meta: dict | None = None,):
    from utils.payment_instructions import resolve_payment_instructions
    instr = (payment_instructions or "").strip() or resolve_payment_instructions(None, lang)
    _send_whatsapp("contribution_target_set", phone, {
        "contributor_name": contributor_name,
        "event_name": event_title,
        "target_text": _money(target, currency),
        "payment_instructions": instr,
        "organizer_phone": organizer_phone or "Nuru",
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #14a/14b — contribution_target_updated
# ──────────────────────────────────────────────
def wa_contribution_target_updated(
    phone: str,
    contributor_name: str,
    event_title: str,
    increase: float,
    total_target: float,
    currency: str = "TZS",
    organizer_phone: str = "",
    lang: str = "sw",
    payment_instructions: str | None = None,
    meta: dict | None = None,):
    from utils.payment_instructions import resolve_payment_instructions
    instr = (payment_instructions or "").strip() or resolve_payment_instructions(None, lang)
    _send_whatsapp("contribution_target_updated", phone, {
        "contributor_name": contributor_name,
        "event_name": event_title,
        "increase_text": _money(increase, currency),
        "total_target_text": _money(total_target, currency),
        "payment_instructions": instr,
        "organizer_phone": organizer_phone or "Nuru",
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #15/16 — contribution_thank_you
# ──────────────────────────────────────────────
def wa_thank_you(
    phone: str,
    contributor_name: str,
    event_title: str,
    amount: float = 0,
    custom_message: str = "",
    organizer_phone: str = "",
    currency: str = "TZS",
    # legacy kwarg kept for backward-compat (was passed as the amount)
    total_paid: float = None,
    lang: str = "sw",
    meta: dict | None = None,):
    eff_amount = amount if amount else (total_paid or 0)
    L = _lang(lang)
    _send_whatsapp("contribution_thank_you", phone, {
        "contributor_name": contributor_name,
        "amount_text": _money(eff_amount, currency),
        "event_name": event_title,
        "custom_message": custom_message or ("Tunakushukuru kwa ukarimu wako." if L == "sw" else "We deeply appreciate your generosity."),
        "organizer_phone": organizer_phone or "Nuru",
        "lang": L,
    }, meta=meta)


# ──────────────────────────────────────────────
# #17/18 — guest_contribution_invite (URL button = share_token)
# ──────────────────────────────────────────────
def wa_guest_contribution_invite(
    phone: str,
    contributor_name: str,
    organiser_name: str,
    event_name: str,
    pledge_amount: float,
    share_token: str,
    currency: str = "TZS",
    lang: str = "sw",
    meta: dict | None = None,):
    _send_whatsapp("guest_contribution_invite", phone, {
        "contributor_name": contributor_name,
        "organiser_name": organiser_name,
        "event_name": event_name,
        "pledge_amount_text": _money(pledge_amount, currency),
        "share_token": share_token,
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #19/20 — guest_contribution_receipt (URL button = receipt_path)
# ──────────────────────────────────────────────
def wa_guest_contribution_receipt(
    phone: str,
    contributor_name: str,
    event_name: str,
    amount: float,
    total_paid: float,
    balance: float,
    transaction_code: str,
    receipt_path: str,
    currency: str = "TZS",
    lang: str = "sw",
    meta: dict | None = None,):
    _send_whatsapp("guest_contribution_receipt", phone, {
        "contributor_name": contributor_name,
        "amount_text": _money(amount, currency),
        "event_name": event_name,
        "total_paid_text": _money(total_paid, currency),
        "balance_text": _money(balance, currency),
        "transaction_code": transaction_code,
        "receipt_path": receipt_path,
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #21/22 — payment_received_generic
# ──────────────────────────────────────────────
def wa_payment_received_generic(phone, amount, payer_name, purpose, transaction_code, currency="TZS", lang="sw"):
    _send_whatsapp("payment_received_generic", phone, {
        "amount_text": _money(amount, currency),
        "payer_name": payer_name,
        "purpose": purpose,
        "transaction_code": transaction_code,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #23/24 — payment_confirmation_payer
# ──────────────────────────────────────────────
def wa_payment_confirmation_payer(phone, payer_name, amount, purpose, transaction_code, currency="TZS", lang="sw"):
    _send_whatsapp("payment_confirmation_payer", phone, {
        "payer_name": payer_name,
        "amount_text": _money(amount, currency),
        "purpose": purpose,
        "transaction_code": transaction_code,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #25/26 — organiser_contribution_received
# ──────────────────────────────────────────────
def wa_organiser_contribution_received(phone, organizer_name, amount, contributor_name, event_name, transaction_code, currency="TZS", lang="sw"):
    _send_whatsapp("organiser_contribution_received", phone, {
        "organizer_name": organizer_name,
        "amount_text": _money(amount, currency),
        "contributor_name": contributor_name,
        "event_name": event_name,
        "transaction_code": transaction_code,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #27/28 — vendor_booking_paid
# ──────────────────────────────────────────────
def wa_vendor_booking_paid(phone, vendor_name, amount, client_name, service_title, service_amount, total_paid, balance, transaction_code, currency="TZS", lang="sw"):
    _send_whatsapp("vendor_booking_paid", phone, {
        "vendor_name": vendor_name,
        "amount_text": _money(amount, currency),
        "client_name": client_name,
        "service_title": service_title,
        "service_amount_text": _money(service_amount, currency),
        "total_paid_text": _money(total_paid, currency),
        "balance_text": _money(balance, currency),
        "transaction_code": transaction_code,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #29/30 — admin_payment_alert
# ──────────────────────────────────────────────
def wa_admin_payment_alert(phone, amount, method, purpose, target_label, payer_name, payer_phone, transaction_code, currency="TZS", lang="sw"):
    _send_whatsapp("admin_payment_alert", phone, {
        "amount_text": _money(amount, currency),
        "method": method,
        "purpose": purpose,
        "target_label": target_label or "",
        "payer_name": payer_name,
        "payer_phone": payer_phone,
        "transaction_code": transaction_code,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #35/36 — vendor_confirmation_receipt
# ──────────────────────────────────────────────
def wa_vendor_confirmation_receipt(phone, vendor_first_name, amount, organiser_name, event_name, balance, currency="TZS", lang="sw"):
    _send_whatsapp("vendor_confirmation_receipt", phone, {
        "vendor_first_name": vendor_first_name,
        "amount_text": _money(amount, currency),
        "organiser_name": organiser_name,
        "event_name": event_name,
        "balance_text": _money(balance, currency),
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #37/38 — vendor_confirmation_receipt_full
# ──────────────────────────────────────────────
def wa_vendor_confirmation_receipt_full(phone, vendor_first_name, amount, organiser_name, event_name, currency="TZS", lang="sw"):
    _send_whatsapp("vendor_confirmation_receipt_full", phone, {
        "vendor_first_name": vendor_first_name,
        "amount_text": _money(amount, currency),
        "organiser_name": organiser_name,
        "event_name": event_name,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #39/40 — organiser_committee_vendor_confirmed
# ──────────────────────────────────────────────
def wa_organiser_committee_vendor_confirmed(phone, recipient_first_name, vendor_name, amount, organiser_name, event_name, balance, currency="TZS", lang="sw"):
    _send_whatsapp("organiser_committee_vendor_confirmed", phone, {
        "recipient_first_name": recipient_first_name,
        "vendor_name": vendor_name,
        "amount_text": _money(amount, currency),
        "organiser_name": organiser_name,
        "event_name": event_name,
        "balance_text": _money(balance, currency),
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #41/42 — expense_recorded
# ──────────────────────────────────────────────
def wa_expense_recorded(phone, recipient_first_name, recorder_name, amount, category, event_name, currency="TZS", lang="sw"):
    _send_whatsapp("expense_recorded", phone, {
        "recipient_first_name": recipient_first_name,
        "recorder_name": recorder_name,
        "amount_text": _money(amount, currency) if not isinstance(amount, str) else amount,
        "category": category,
        "event_name": event_name,
        "lang": _lang(lang),
    })


# ──────────────────────────────────────────────
# #43/44 — service_booking_notification
# ──────────────────────────────────────────────
def wa_booking_notification(phone, provider_name, event_title, client_name, service_name="service", lang="sw",
    meta: dict | None = None):
    _send_whatsapp("service_booking_notification", phone, {
        "provider_name": provider_name,
        "client_name": client_name,
        "service_name": service_name or "service",
        "event_name": event_title,
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# #45/46 — booking_accepted
# ──────────────────────────────────────────────
def wa_booking_accepted(phone, requester_first_name, vendor_name, service_name, event_title, lang="sw",
    meta: dict | None = None):
    _send_whatsapp("booking_accepted", phone, {
        "requester_first_name": requester_first_name,
        "vendor_name": vendor_name,
        "service_name": service_name,
        "event_name": event_title,
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# DEPRECATED — kept as no-op shims for safety during deploy overlap.
# These map to the new templates above. Remove after one full deploy cycle.
# ──────────────────────────────────────────────
def wa_event_updated(phone, *args, **kwargs):
    """DEPRECATED — event_update was removed from the catalogue."""
    return False


def wa_event_reminder(*args, **kwargs):
    """Routes to the reminder-automation template (kept as-is per catalogue)."""
    if len(args) >= 1:
        phone = args[0]
    else:
        phone = kwargs.get("phone", "")
    if not phone:
        return False
    _send_whatsapp("reminder", phone, {
        "guest_name": kwargs.get("guest_name", args[1] if len(args) > 1 else ""),
        "event_name": kwargs.get("event_name", args[2] if len(args) > 2 else ""),
        "event_date": kwargs.get("event_date", args[3] if len(args) > 3 else ""),
        "event_time": kwargs.get("event_time", args[4] if len(args) > 4 else ""),
        "location": kwargs.get("location", args[5] if len(args) > 5 else ""),
    })


# ──────────────────────────────────────────────
# Pledge thank-you card (image header + 2 body params)
# Templates: nuru_pledge_thank_you_card_sw / _en
# ──────────────────────────────────────────────
def wa_pledge_thank_you_card(
    phone: str,
    contributor_name: str,
    event_name: str,
    image_url: str,
    lang: str = "sw",
    meta: dict | None = None,):
    return _send_whatsapp("pledge_thank_you_card", phone, {
        "contributor_name": contributor_name or "Friend",
        "event_name": event_name or "the event",
        "image_url": image_url or "",
        "lang": _lang(lang),
    }, meta=meta)


# ──────────────────────────────────────────────
# Event invitation card (image header + 6 body params)
# Templates: invitation_card_sw / invitation_card_en
# Body: {{1}} guest_name · {{2}} organizer_name · {{3}} event_name ·
#       {{4}} event_date · {{5}} venue · {{6}} organizer_phone
# ──────────────────────────────────────────────
def wa_event_invitation_card(
    phone: str,
    guest_name: str,
    event_name: str,
    image_url: str,
    organizer_name: str = "",
    organizer_phone: str = "",
    event_date: str = "",
    venue: str = "",
    lang: str = "sw",
    meta: dict | None = None,):
    return _send_whatsapp("invitation_card_message", phone, {
        "guest_name": guest_name or "Guest",
        "organizer_name": organizer_name or "Your host",
        "event_name": event_name or "the event",
        "event_date": event_date or "TBA",
        "venue": venue or "TBA",
        "organizer_phone": organizer_phone or "—",
        "image_url": image_url or "",
        "lang": _lang(lang),
    }, meta=meta)
