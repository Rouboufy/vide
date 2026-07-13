# Engineering backlog

This file tracks remaining structural improvements. Completed refactors should
be removed rather than retained as historical recommendations.

## UI primitives

Native widgets still duplicate modal backgrounds, borders, buttons, lists,
scrolling, clipping, and hit testing. Introduce a small toolkit whose drawing
and interaction geometry come from the same rectangles. This will reduce
coordinate drift and make keyboard focus consistent.

## Unicode cell width

The native text renderer currently advances one column per Unicode code point.
It needs terminal-cell width handling for wide and combining characters.
Neovim grid continuation cells and native labels should share the same width
rules, with tests for CJK, emoji, combining marks, and optional Nerd Font
symbols.

## Error visibility

Many non-critical widget refreshes intentionally continue after failure, but
users need a native notification surface and logs need structured context.
Replace silent catches at subsystem boundaries with visible, non-blocking
errors while keeping render-loop failures recoverable.

## Test harness

Add pseudo-terminal integration tests that launch an isolated fake or real
Neovim instance and verify startup, mode transitions, resize, paste, mouse
input, buffer synchronization, and terminal restoration after failures.
