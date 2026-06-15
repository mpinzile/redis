"""Audio transcoding helpers for the Nuru Voice Assistant (Phase 5).

Twilio Media Streams emit and accept G.711 μ-law (mulaw) at 8 kHz, mono,
base64-encoded inside JSON frames. Gemini Live works in linear PCM16. We
keep the conversion in one tiny module so the WebSocket bridge stays
focused on protocol/state.

We use ``audioop`` from the stdlib for the actual transcoding so we don't
pull in numpy or scipy on the realtime hot path. Python 3.13 deprecates
``audioop``; if the build host removes it we fall back to a pure-Python
implementation that's slower but correct.
"""
from __future__ import annotations

import base64
from typing import Optional

try:  # pragma: no cover - exercised at import time
    import audioop  # type: ignore
    _HAVE_AUDIOOP = True
except Exception:  # noqa: BLE001
    audioop = None  # type: ignore
    _HAVE_AUDIOOP = False


# Twilio Media Streams contract.
TWILIO_SAMPLE_RATE = 8000
TWILIO_CHANNELS = 1
TWILIO_SAMPLE_WIDTH = 2  # PCM16 width after we decode mulaw

# Gemini Live expects 16 kHz PCM16 input and emits 24 kHz PCM16 output.
GEMINI_INPUT_RATE = 16000
GEMINI_OUTPUT_RATE = 24000


def mulaw_b64_to_pcm16(payload_b64: str, *, target_rate: int = GEMINI_INPUT_RATE) -> bytes:
    """Decode Twilio's base64 mulaw chunk and return PCM16 at ``target_rate``."""
    if not payload_b64:
        return b""
    raw = base64.b64decode(payload_b64)
    if not _HAVE_AUDIOOP:
        # Fallback path: keep at 8k mulaw decoded via lookup table.
        pcm = _mulaw_decode_pure(raw)
    else:
        pcm = audioop.ulaw2lin(raw, TWILIO_SAMPLE_WIDTH)
    if target_rate != TWILIO_SAMPLE_RATE and _HAVE_AUDIOOP:
        pcm, _ = audioop.ratecv(
            pcm, TWILIO_SAMPLE_WIDTH, TWILIO_CHANNELS,
            TWILIO_SAMPLE_RATE, target_rate, None,
        )
    return pcm


def pcm16_to_mulaw_b64(pcm: bytes, *, source_rate: int = GEMINI_OUTPUT_RATE) -> str:
    """Convert PCM16 from the AI provider to base64 mulaw that Twilio accepts."""
    if not pcm:
        return ""
    data = pcm
    if source_rate != TWILIO_SAMPLE_RATE and _HAVE_AUDIOOP:
        data, _ = audioop.ratecv(
            data, TWILIO_SAMPLE_WIDTH, TWILIO_CHANNELS,
            source_rate, TWILIO_SAMPLE_RATE, None,
        )
    if _HAVE_AUDIOOP:
        mulaw = audioop.lin2ulaw(data, TWILIO_SAMPLE_WIDTH)
    else:
        mulaw = _mulaw_encode_pure(data)
    return base64.b64encode(mulaw).decode("ascii")


# ──────────────────────────────────────────────────────────────────
# Pure-Python fallbacks (only used when audioop is unavailable).
# Reference: ITU-T G.711 μ-law, RFC 8866 §C.1.
# ──────────────────────────────────────────────────────────────────

_BIAS = 0x84
_CLIP = 32635


def _mulaw_encode_sample(sample: int) -> int:
    sign = 0x80 if sample < 0 else 0
    if sign:
        sample = -sample
    if sample > _CLIP:
        sample = _CLIP
    sample += _BIAS
    exponent = 7
    mask = 0x4000
    while exponent and not (sample & mask):
        exponent -= 1
        mask >>= 1
    mantissa = (sample >> (exponent + 3)) & 0x0F
    return (~(sign | (exponent << 4) | mantissa)) & 0xFF


def _mulaw_decode_sample(byte: int) -> int:
    byte = ~byte & 0xFF
    sign = byte & 0x80
    exponent = (byte >> 4) & 0x07
    mantissa = byte & 0x0F
    sample = ((mantissa << 3) + _BIAS) << exponent
    sample -= _BIAS
    return -sample if sign else sample


def _mulaw_decode_pure(buf: bytes) -> bytes:
    out = bytearray(len(buf) * 2)
    for i, b in enumerate(buf):
        s = _mulaw_decode_sample(b)
        out[2 * i] = s & 0xFF
        out[2 * i + 1] = (s >> 8) & 0xFF
        if s < 0:
            # Two's-complement little-endian 16-bit.
            s &= 0xFFFF
            out[2 * i] = s & 0xFF
            out[2 * i + 1] = (s >> 8) & 0xFF
    return bytes(out)


def _mulaw_encode_pure(buf: bytes) -> bytes:
    out = bytearray(len(buf) // 2)
    for i in range(0, len(buf), 2):
        lo = buf[i]
        hi = buf[i + 1]
        sample = lo | (hi << 8)
        if sample >= 0x8000:
            sample -= 0x10000
        out[i // 2] = _mulaw_encode_sample(sample)
    return bytes(out)


def silence_mulaw_b64(duration_ms: int = 20) -> str:
    """Return a base64 mulaw payload of silence at 8 kHz for ``duration_ms``."""
    n = max(1, int(TWILIO_SAMPLE_RATE * (duration_ms / 1000.0)))
    return base64.b64encode(b"\xff" * n).decode("ascii")
