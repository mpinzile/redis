"""Tests for natural Swahili conversation classification (Phase 11)."""
from voice.agents.conversation import classify


def _check(text, intent):
    t = classify(text)
    assert t.intent == intent, f"{text!r} -> {t.intent} (expected {intent})"


def test_direct_confirmed():
    _check("Ndio nitakuja", "confirmed")
    _check("Yes", "confirmed")


def test_indirect_confirmed():
    _check("Inshallah nitakuja", "confirmed")
    _check("Mungu akipenda nitakuja", "confirmed")
    _check("Tupo pamoja", "confirmed")


def test_direct_declined():
    _check("Sitakuja", "declined")
    _check("Sitaweza kuhudhuria", "declined")


def test_indirect_declined():
    _check("Nina safari siku hiyo", "declined")
    _check("Niko kazini", "declined")


def test_maybe():
    _check("Bado sijajua", "maybe")
    _check("Labda", "maybe")


def test_call_later():
    _check("Nipigie baadaye", "call_later")
    _check("Nipigie kesho", "call_later")


def test_wrong_number():
    _check("Umekosea namba", "wrong_number")
    _check("Mimi sio huyo", "wrong_number")


def test_identity_question():
    _check("Wewe ni nani?", "identity_question")
    _check("Namba yangu mmeipata wapi?", "identity_question")


def test_did_not_hear():
    _check("Sikusikii vizuri", "did_not_hear")
    _check("Rudia tafadhali", "did_not_hear")


def test_noisy_environment():
    t = classify("Kuna kelele hapa, sauti inakatika")
    assert t.intent == "noisy_environment"
    assert t.noise_detected is True


def test_silence():
    t = classify("")
    assert t.intent == "silence"


def test_angry():
    t = classify("Msinisumbue tena")
    assert t.intent == "angry_or_uncomfortable"
    assert t.mood == "angry"


def test_request_whatsapp():
    _check("Nitumie ujumbe WhatsApp", "request_whatsapp")


def test_unclear():
    t = classify("Eeeh basi sijui hivyo")
    assert t.intent == "unclear"
    assert t.confidence < 0.6


def test_priority_identity_beats_rsvp():
    # "wewe ni nani, nitakuja?" must be classified as identity question first.
    _check("Wewe ni nani, nitakuja?", "identity_question")


def test_declined_beats_confirmed_substring():
    # "sitakuja" contains "nitakuja" — declined must win.
    _check("Sitakuja kabisa", "declined")


def test_next_state_for_confirmed_is_closing():
    assert classify("Ndio nitakuja").next_state == "closing"


def test_next_state_for_noisy_routes_to_whatsapp():
    assert classify("Kuna kelele").next_state == "whatsapp_follow_up"
