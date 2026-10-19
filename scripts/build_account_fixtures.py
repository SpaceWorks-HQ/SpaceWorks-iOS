"""Build synthetic account examples from the same pinned schema as the generated client."""
import base64
import io
import json
import zipfile
from build_staff_fixtures import ROOT, model


def build():
    current = "83000000-0000-4000-8000-000000000001"
    other = "83000000-0000-4000-8000-000000000002"
    fixtures = {
        "sessions": model("AccountSessionPage", count=2, results=[
            model("AccountSession", id="device:" + current, kind="device", current=True),
            model("AccountSession", id="web:sample-other-session", kind="web", current=False),
        ]),
        "grants": [model("DeviceGrant", id=current, platform="apple", app_id="org.spaceworks.app", environment="development", status="active"),
                   model("DeviceGrant", id=other, platform="android", app_id="org.spaceworks.app", environment="development", status="active")],
        "membership": model("MembershipAccount", status="active"),
        "mfa": model("MFAStatus", available=True, enabled=True, required=False),
        "challenge": model("MFAChallengeResponse", mfa_required=True, enrollment_required=True, challenge="demo-account-challenge", expires_in=300),
        "recovery": model("MFARecovery", recovery_codes=["demo-recovery-01", "demo-recovery-02", "demo-recovery-03"]),
        "provider": model("SocialIdentity", provider="google"),
        "export": model("SubjectExport", id="84000000-0000-4000-8000-000000000001", status="available", failure_code="", failure_detail="", manifest={"demo": True}, expires_at="2099-01-01T00:00:00Z"),
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        info = zipfile.ZipInfo("README.txt", date_time=(2026, 10, 16, 9, 0, 0))
        archive.writestr(info, "SPACE WORKS DEMO EXPORT\nSample data only. No personal account data is included.\n")
    fixtures["archive"] = {"base64": base64.b64encode(buffer.getvalue()).decode("ascii")}
    directory = ROOT / "Fixtures/Account"
    directory.mkdir(parents=True, exist_ok=True)
    for name, value in fixtures.items():
        (directory / (name + ".json")).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
