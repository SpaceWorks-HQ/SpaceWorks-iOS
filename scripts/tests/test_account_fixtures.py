import base64
import io
import json
import zipfile
import test_staff_fixtures


class AccountFixturesTests(test_staff_fixtures.StaffFixturesTests):
    directory = "Account"
    models = {
        "sessions": "AccountSessionPage", "membership": "MembershipAccount", "mfa": "MFAStatus",
        "challenge": "MFAChallengeResponse", "recovery": "MFARecovery", "provider": "SocialIdentity", "export": "SubjectExport",
        "grants": {"type": "array", "items": {"$ref": "#/components/schemas/DeviceGrant"}},
    }

    def test_sample_archive_is_a_valid_zip_containing_only_explicit_demo_data(self):
        fixture = test_staff_fixtures.ROOT / "Fixtures/Account/archive.json"
        data = base64.b64decode(json.loads(fixture.read_text(encoding="utf-8"))["base64"])
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            self.assertEqual(archive.namelist(), ["README.txt"])
            self.assertIn("SPACE WORKS DEMO EXPORT", archive.read("README.txt").decode("utf-8"))
