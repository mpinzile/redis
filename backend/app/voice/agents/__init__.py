"""Voice agents package (Phase 7 of nuru_voice.md).

Each agent module owns a system prompt + Gemini Live tool schema + the
backend tool executors. ``rsvp_agent`` is the default and is wired into
``voice.ai`` at startup.
"""
from voice.agents.rsvp_agent import (
    build_rsvp_spec, execute_tool, install_rsvp_agent,
)

__all__ = ["build_rsvp_spec", "execute_tool", "install_rsvp_agent"]
