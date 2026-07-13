#!/usr/bin/env python3
import json
from pathlib import Path

profile = json.loads(Path("docs/performance-profile.json").read_text(encoding="utf-8"))
scenarios = profile["scenarios"]
required = {"startup_offline", "large_file", "large_directory", "plugin_initialization"}
assert required <= scenarios.keys()
assert scenarios["large_file"]["bytes"] >= 5_000_000
assert scenarios["large_directory"]["entries"] >= 5_000
for name in required:
    result = scenarios[name]
    if result["available"]:
        assert result["exit_status"] == 0, f"{name} did not exit cleanly"
assert scenarios["startup_offline"]["redraw_storm_ms"] is not None
assert scenarios["startup_offline"]["redraw_output_bytes"] > 0
print("Performance profile validated")
