"""Rebuild synthetic A6 fixtures from the pinned schema. These are never live server records."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCHEMAS = json.loads((ROOT / "api/openapi.json").read_text(encoding="utf-8"))["components"]["schemas"]


def example(schema):
    if schema.get("nullable"):
        return None
    if "$ref" in schema:
        return example(SCHEMAS[schema["$ref"].split("/")[-1]])
    if "allOf" in schema:
        return example(schema["allOf"][0])
    if "enum" in schema:
        return schema["enum"][0]
    kind = schema.get("type")
    if kind == "object":
        return {name: example(schema["properties"][name]) for name in schema.get("required", [])}
    if kind == "array":
        return []
    if kind == "boolean":
        return False
    if kind in ("integer", "number"):
        return max(0, schema.get("minimum", 0))
    if kind == "string":
        if schema.get("format") == "date-time":
            return "2026-10-16T09:00:00Z"
        if schema.get("format") == "uuid":
            return "71000000-0000-4000-8000-000000000001"
        if schema.get("format") == "decimal":
            return "0.00"
        return ""
    return None


def model(schema_name, **changes):
    return example(SCHEMAS[schema_name]) | changes


def build():
    item = model("AdminRequestItem", id=61, product_id=901, product_name="Sample precision toolkit", requested_quantity=2,
                 accepted_quantity=2, issued_quantity=2, tracking_mode="quantity", storage_location="Sample shelf A")
    request = model("AdminRequest", id=601, makerspace_id=7, requester_username="meera", requester_name="Meera Nair",
                    requester_display="Meera Nair", requester_contact_email="meera@example.test", requester_contact_verified=True,
                    status="pending", items=[item], requested_for="Sample electronics project", assigned_box_label="Sample kit box")
    fixtures = {
        "request": request,
        "loan": model("DirectLoan", id=701, target_type="product", target_label="Sample precision toolkit", status="active",
                      container_id=0, source="staff", items=[{"product_name": "Sample precision toolkit", "quantity": 2}],
                      return_items=[model("DirectLoanReturnItem", item_id=71, product_name="Sample precision toolkit", remaining_quantity=2, tracking_mode="quantity")]),
        "members": model("PaginatedDirectLoanMemberList", count=1, results=[model("DirectLoanMember", user_id=51, membership_id=81, display_name="Meera Nair", username="meera")]),
        "inventory": model("PaginatedInventoryProductAdminList", count=1, results=[model("InventoryProductAdmin", id=901, makerspace=7, name="Sample precision toolkit", tracking_mode="quantity", available_quantity=4, total_quantity=4, is_archived=False)]),
        "containers": model("PaginatedBoxList", count=0, results=[]),
        "event": model("EventAdmin", id=801, makerspace_id=7, title="Sample repair workshop", status="published", location="Sample workshop", capacity=20),
        "space": model("BookableSpaceAdmin", id=901, makerspace_id=7, name="Sample project room", is_active=True, capacity=8),
        "booking": model("BookingAdmin", id=1001, space_id=901, name="Meera Nair", email="meera@example.test", status="pending"),
        "registration": model("EventRegistrationAdmin", id=1101, event_id=801, name="Meera Nair", email="meera@example.test", status="registered"),
        "checkin": model("EventCheckInResolveResponse", registration_id=1101, name="Meera Nair", status="registered", payment_status="not_required", event_status="published", confirmable=True),
        "kits": model("KitPreview", components=[model("KitExpectation", key="72000000-0000-4000-8000-000000000001", label="Sample probe", owner_label="Precision toolkit", quantity=2)]),
        "qr": model("QrResolveResult", qr=model("QrCode", id=1201, makerspace=7, payload="DEMO-BOX", target_type="box", target_id=91, status="active"), target={"type": "box", "id": 91, "label": "Sample kit box"}, allowed_actions=["view", "contents", "record_scan"]),
    }
    directory = ROOT / "Fixtures/Staff"
    directory.mkdir(parents=True, exist_ok=True)
    for name, value in fixtures.items():
        (directory / (name + ".json")).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
