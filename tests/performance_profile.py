#!/usr/bin/env python3
import json, re
from pathlib import Path

PROFILE = Path(__file__).resolve().parents[1] / "docs/performance-profile.json"
profile = json.loads(PROFILE.read_text(encoding="utf-8"))
assert profile["schema_version"] == 2
assert profile["configuration"]["iterations"] >= 1
assert profile["configuration"]["warmup"] >= 0
assert isinstance(profile["configuration"]["seed"], int)

for name, artifact in profile["artifacts"].items():
    assert re.fullmatch(r"[0-9a-f]{64}", artifact["sha256"]), f"invalid {name} SHA256"
    for field in ("git_commit", "zig_version", "target", "optimization_mode"):
        assert artifact[field] and artifact[field] != "unknown", f"missing {name} {field}"
    assert artifact["file_size"] > 0

required = {"startup", "normal_typing_navigation", "git_view_idle_refresh",
            "large_directory", "large_file", "resize_storms",
            "terminal_output_bursts", "idle_wakeups", "plugin_initialization"}
summary_fields = {"min", "max", "mean", "median", "p50", "p95", "p99", "stddev"}
iterations = profile["configuration"]["iterations"]

for artifact_name, artifact_profile in profile["profiles"].items():
    scenarios = artifact_profile["scenarios"]
    assert required == scenarios.keys(), f"scenario mismatch for {artifact_name}"
    assert scenarios["large_file"]["fixture_bytes"] >= 5_000_000
    assert scenarios["large_file"]["fixture_lines"] == 120_000
    assert scenarios["large_directory"]["fixture_entries"] == 5_000
    for scenario_name, scenario in scenarios.items():
        assert scenario["iterations"] == iterations
        if not scenario["available"]:
            assert scenario_name == "plugin_initialization" and scenario.get("reason")
            continue
        assert scenario["clean_exits"], f"{artifact_name}/{scenario_name} did not exit cleanly"
        assert scenario["exit_status_samples"] == [0] * iterations
        assert scenario["terminal_visible"], f"no terminal samples for {scenario_name}"
        for section_name in ("terminal_visible", "local"):
            for metric_name, metric in scenario[section_name].items():
                assert len(metric["samples"]) == iterations, f"raw samples missing for {scenario_name}/{metric_name}"
                assert summary_fields == metric["summary"].keys()
                for field in ("mean", "p50", "p95", "p99", "max"):
                    assert metric["summary"][field] is not None
        if scenario_name != "plugin_initialization":
            assert scenario["local"], f"diagnostics missing for {scenario_name}"

if "baseline" in profile["profiles"]:
    assert required == profile["comparison"].keys()
    for metrics in profile["comparison"].values():
        for comparison in metrics.values():
            assert {"baseline_mean", "candidate_mean", "delta", "percent_change", "regression"} == comparison.keys()
            assert isinstance(comparison["regression"], bool)
print("Performance profile validated")
