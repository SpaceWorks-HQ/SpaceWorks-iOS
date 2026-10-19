"""Build DEBUG-only fixture constants; raw fixture files never enter the application resource bundle."""
import pathlib


def generate_member_fixtures(root):
    root = pathlib.Path(root)
    lines = ["// Generated synthetic contract fixtures. No Release implementation.", "#if DEBUG", "enum DebugMemberFixtures {"]
    for source in sorted((root / "Fixtures/Member").glob("*.json")):
        text = source.read_text(encoding="utf-8").strip()
        if '"""#' in text or '\\#(' in text or not source.stem.isidentifier():
            raise ValueError("Unsafe raw Swift literal")
        lines.append(f'    static let {source.stem} = #"""\n{text}\n"""#')
    lines.extend(["}", "#endif", ""])
    (root / "SpaceWorks/Generated/DebugMemberFixtures.swift").write_text("\n".join(lines), encoding="utf-8")
