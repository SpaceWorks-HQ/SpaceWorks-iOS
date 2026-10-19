"""Synthetic account data is compiled only in Debug and never bundled as raw resources."""
import pathlib


def generate_account_fixtures(root):
    root = pathlib.Path(root)
    lines = ["// Generated synthetic A7 fixtures.", "#if DEBUG", "enum DebugAccountFixtures {"]
    for source in sorted((root / "Fixtures/Account").glob("*.json")):
        value = source.read_text(encoding="utf-8").strip()
        if not source.stem.isidentifier() or '"""#' in value or "\\#(" in value:
            raise ValueError("Unsafe raw Swift literal")
        lines.append(f'    static let {source.stem} = #"""\n{value}\n"""#')
    lines.extend(["}", "#endif", ""])
    destination = root / "SpaceWorks/Generated/DebugAccountFixtures.swift"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8")
