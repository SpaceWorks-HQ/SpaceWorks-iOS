"""Check synthetic staff data against the pinned OpenAPI types, rather than a second fixture model."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODELS = {
    "request": "AdminRequest", "loan": "DirectLoan", "members": "PaginatedDirectLoanMemberList",
    "inventory": "PaginatedInventoryProductAdminList", "containers": "PaginatedBoxList",
    "event": "EventAdmin", "space": "BookableSpaceAdmin", "booking": "BookingAdmin",
    "registration": "EventRegistrationAdmin", "checkin": "EventCheckInResolveResponse",
    "kits": "KitPreview", "qr": "QrResolveResult",
}


class StaffFixturesTests(unittest.TestCase):
    models = MODELS
    directory = "Staff"
    def test_synthetic_records_satisfy_authoritative_required_fields_enums_types_and_bounds(self):
        schemas = json.loads((ROOT / "api/openapi.json").read_text(encoding="utf-8"))["components"]["schemas"]

        def check(value, schema, path):
            if value is None and schema.get("nullable"):
                return
            if "$ref" in schema:
                return check(value, schemas[schema["$ref"].split("/")[-1]], path)
            if "allOf" in schema:
                for component in schema["allOf"]:
                    check(value, component, path)
                return
            if "enum" in schema:
                self.assertIn(value, schema["enum"], path)
            kind = schema.get("type")
            if kind == "object":
                self.assertIsInstance(value, dict, path)
                for key in schema.get("required", []):
                    self.assertIn(key, value, path)
                for key, child in value.items():
                    if key in schema.get("properties", {}):
                        check(child, schema["properties"][key], path + "." + key)
            elif kind == "array":
                self.assertIsInstance(value, list, path)
                for index, child in enumerate(value):
                    check(child, schema["items"], path + "." + str(index))
            elif kind in ("integer", "number"):
                self.assertIsInstance(value, (int, float), path)
                self.assertNotIsInstance(value, bool, path)
                self.assertGreaterEqual(value, schema.get("minimum", value), path)
                self.assertLessEqual(value, schema.get("maximum", value), path)
            elif kind == "string":
                self.assertIsInstance(value, str, path)
            elif kind == "boolean":
                self.assertIsInstance(value, bool, path)

        for filename, model in self.models.items():
            with self.subTest(model=model):
                fixture = json.loads((ROOT / "Fixtures" / self.directory / (filename + ".json")).read_text(encoding="utf-8"))
                check(fixture, schemas[model] if isinstance(model, str) else model, filename)


if __name__ == "__main__":
    unittest.main()
