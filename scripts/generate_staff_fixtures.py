"""Compile synthetic staff fixtures into DEBUG-only constants, never application resources."""
import pathlib


def generate_staff_fixtures(root):
    root = pathlib.Path(root)
    lines = ["// Generated synthetic A6 fixtures.", "#if DEBUG", "enum DebugStaffFixtures {"]
    for source in sorted((root / "Fixtures/Staff").glob("*.json")):
        value = source.read_text(encoding="utf-8").strip()
        if not source.stem.isidentifier() or '"""#' in value or "\\#(" in value:
            raise ValueError("Unsafe raw Swift literal")
        lines.append(f'    static let {source.stem} = #"""\n{value}\n"""#')
    lines.extend(["}", "#endif", ""])
    destination = root / "SpaceWorks/Generated/DebugStaffFixtures.swift"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8")
