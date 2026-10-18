"""Check synthetic member data against the generated operation response schemas it is decoded as."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OPERATIONS = {
    "activity": "api_v1_member_makerspaces_activity_retrieve",
    "bookings": "api_v1_public_my_bookings_retrieve",
    "bootstrap": "api_v1_bootstrap_retrieve",
    "card": "api_v1_member_makerspaces_member_card_retrieve",
    "categories": "api_v1_public_inventory_categories_list",
    "events": "api_v1_public_events_list",
    "inbox": "api_v1_notifications_inbox_retrieve",
    "inventory": "api_v1_public_inventory_list",
    "spaces": "api_v1_public_spaces_list",
}


class MemberFixturesTests(unittest.TestCase):
    def test_member_fixtures_satisfy_their_operation_response_schemas(self):
        document = json.loads((ROOT / "api/openapi.json").read_text(encoding="utf-8"))
        schemas = document["components"]["schemas"]
        operations = {operation["operationId"]: operation for path in document["paths"].values()
                      for operation in path.values() if isinstance(operation, dict) and "operationId" in operation}

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
            elif kind == "integer":
                self.assertIsInstance(value, int, path)
                self.assertNotIsInstance(value, bool, path)
            elif kind == "string":
                self.assertIsInstance(value, str, path)
            elif kind == "boolean":
                self.assertIsInstance(value, bool, path)

        for name, operation in OPERATIONS.items():
            with self.subTest(fixture=name):
                schema = operations[operation]["responses"]["200"]["content"]["application/json"]["schema"]
                fixture = json.loads((ROOT / "Fixtures/Member" / (name + ".json")).read_text(encoding="utf-8"))
                check(fixture, schema, name)


if __name__ == "__main__":
    unittest.main()
