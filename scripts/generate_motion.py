"""Generate native motion only from the pinned shared Design contract."""
import json
import pathlib


def render_motion(document):
    durations = document["duration_ms"]
    if document["onboarding"]["logo_motion"] != "none" or document["onboarding"]["blocking_delay_ms"] != 0:
        raise ValueError("The master stays static and onboarding never blocks interaction")
    reduced = document["reduce_motion"]
    if reduced["spatial_transitions"] or reduced["decorative_repeats"] or reduced["blocking_delay_ms"] or reduced["opacity_duration_ms"]:
        raise ValueError("Reduced motion must remove all custom movement and delays")
    if any(not isinstance(value, int) or value < 0 or value > 1000 for value in durations.values()):
        raise ValueError("Invalid duration")
    curve = document["easing"]["overlay_enter_cubic_bezier"]
    if len(curve) != 4 or any(not isinstance(value, (int, float)) or not 0 <= value <= 1 for value in curve):
        raise ValueError("Invalid motion curve")
    constants = "\n".join(f"    static let {name}: Double = {durations[key] / 1000:g}" for name, key in [
        ("color", "color"), ("expand", "expand"), ("overlayEnter", "overlay_enter"), ("overlayExit", "overlay_exit")])
    return ("// Generated from design/tokens/mobile-motion.json. Do not edit.\nimport SwiftUI\nenum MobileMotion {\n"
            + constants + "\n    static let expandAnimation = Animation.timingCurve("
            + ", ".join(f"{value:g}" for value in curve) + ", duration: expand)\n}\n")


def generate_motion(root):
    root = pathlib.Path(root)
    document = json.loads((root / "design/tokens/mobile-motion.json").read_text())
    (root / "SpaceWorks/Generated/MobileMotion.swift").write_text(render_motion(document), encoding="utf-8")
