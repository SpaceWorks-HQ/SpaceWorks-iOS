# Synthetic member contract fixtures

These records are invented sample content decoded through the exact generated API schemas in native tests and the explicitly labelled Debug demo. They are not a live backend response or production cache. The generator places them inside a `#if DEBUG` Swift source file; this directory is outside the app resource target and is not bundled in Release.

Use the generated models and the source contract's field names/status values. Keep availability, dues, membership-card state and server status authoritative in production. Sample payment or staff results never authorize a live action.
