"""Seed English app-owned literal keys; Xcode extracts interpolated keys at build time.

Run manually after copy changes. Existing translations are retained. This never scans
API responses, user input, fixtures, generated clients, keys, URLs, or provider IDs.
"""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "SpaceWorks/Resources/Localizable.xcstrings"
LITERAL = r'"((?:[^"\\]|\\.)*)"'
CALL = re.compile(r'(?:\b(?:Text|Button|Label|ProgressView|NavigationLink|Toggle|Picker|TextField|SecureField|LocalizedStringKey)|\.(?:navigationTitle|accessibilityLabel))\(\s*' + LITERAL)
OWNED_LABEL = re.compile(r'\b(?:StaffMenuRow|AccountMenuRow)\(\s*title:\s*' + LITERAL)
OWNED_DETAIL = re.compile(r'\bStaffMenuRow\([^\n]*?detail:\s*' + LITERAL)
LOCALIZED = re.compile(r'\bString\(localized:\s*' + LITERAL)


def literal_keys(source):
    values = set()
    for pattern in [CALL, LOCALIZED, OWNED_LABEL, OWNED_DETAIL]:
        for match in pattern.finditer(source):
            raw = match[1]
            if not raw or "\\(" in raw:
                continue  # Preserve interpolation/plurals for the Swift compiler's extraction.
            try:
                value = json.loads('"' + raw + '"')
            except ValueError:
                continue
            values.add(value)
    return values


def update(check=False):
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    strings = catalog["strings"]
    keys = set()
    for source in (ROOT / "SpaceWorks").rglob("*.swift"):
        if "Generated" not in source.parts:
            keys.update(literal_keys(source.read_text(encoding="utf-8")))
    missing = keys - strings.keys()
    if check:
        if missing:
            raise SystemExit("App-owned English catalog keys missing: " + ", ".join(sorted(missing)))
        return
    for key in keys:
        strings.setdefault(key, {"extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": key}}}})
    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"English app catalog contains {len(strings)} keys; existing translations retained.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--check", action="store_true")
    update(parser.parse_args().check)
