# Prompt 07B retained-composition evidence

Recorded 2026-08-27 on the Prompt 03 named local reference setup. The
comparison used an immutable `aa76b7f` Prompt 07A baseline and the Prompt 07B
candidate, both built with Zig 0.16.0 in `ReleaseSafe` mode. The repository's
deterministic profiler ran one warmup and three measured iterations per
scenario with seed 42:

```sh
python3 scripts/profile_vide.py \
  --baseline <immutable-07a-binary> \
  --candidate zig-out/bin/vide \
  --iterations 3 --warmup 1 --optimization ReleaseSafe \
  --output /tmp/prompt07b-profile.json
```

| Scenario / metric | 07A mean | 07B mean | Change |
| --- | ---: | ---: | ---: |
| Normal interaction redraw bytes | 430.67 | 321.00 | -25.46% |
| Normal interaction emitted bytes | 17,614.67 | 17,440.00 | -0.99% |
| Normal interaction composition p99 | 0.318 ms | 0.312 ms | -1.80% |
| Resize-storm composition p99 | 0.302 ms | 0.290 ms | -3.84% |
| Resize-storm idle CPU | 13.33 ms | 10.00 ms | -25.00% |
| Idle-scenario CPU | 3.33 ms | 0.00 ms | -100.00% |
| Idle redraw bytes | 0 | 0 | unchanged |
| Startup output bytes | 17,073 | 17,073 | unchanged |
| Startup settled time | 279.11 ms | 278.95 ms | -0.05% |

ANSI p99 varied between runs (normal interaction +16.92%, resize storm
+21.96%), but remained below 7.8 ms. Composition remained below 0.33 ms in
the named scenarios. Both are well below the 50 ms investigation threshold;
the output-facing measurements did not regress, and normal interaction output
improved. The final current-versus-previous comparison and forced-full-redraw
path remain enabled.

Correctness verification:

```sh
zig build test --summary all
zig build && python3 tests/pty_integration.py
git diff --check
```

The checked fixtures cover independent region retention, cursor-only editor
composition, overlay movement/closure exposing all base regions, canonical
cell repair after an overlay closes or a drawer disappears, and final ANSI
cell comparison through the accepted Prompt 07A encoder.
