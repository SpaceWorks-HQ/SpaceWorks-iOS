"""Small repository-specific lint: API boundaries, secrets, generated assets and source hygiene."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
errors = []
for folder in ["SpaceWorks", "Packages/SpaceWorksAPI/Sources"]:
    for source in (ROOT / folder).rglob("*.swift"):
        if "Generated" in source.parts:
            continue
        text = source.read_text(encoding="utf-8")
        if re.search(r"#[0-9A-Fa-f]{6}\b", text):
            errors.append(f"{source.relative_to(ROOT)}: use generated semantic colors")
        if "SpaceWorks" in source.parts and re.search(r"URLSession\.(shared|data|upload)|WebView|WKWebView", text):
            errors.append(f"{source.relative_to(ROOT)}: server calls belong to generated client package")
        if "PRIVATE KEY-----" in text:
            errors.append(f"{source.relative_to(ROOT)}: embedded private key")
        for number, line in enumerate(text.splitlines(), 1):
            if line != line.rstrip():
                errors.append(f"{source.relative_to(ROOT)}:{number}: trailing whitespace")
if errors:
    raise SystemExit("\n".join(errors))
print("Source boundary, semantic-color, secret and whitespace lint passed.")
