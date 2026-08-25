#!/usr/bin/env python3
"""Render a deterministic 01B facilitator state at an exact terminal size."""

import argparse
from generate_01b import ALTS, STATES, make, valid_state

parser = argparse.ArgumentParser()
parser.add_argument("alternative", choices=ALTS)
parser.add_argument("state", choices=STATES)
parser.add_argument("width", type=int)
parser.add_argument("height", type=int)
args = parser.parse_args()
if args.width < 20 or args.height < 8:
    parser.error("prototype harness minimum is 20x8")
if not valid_state(args.alternative, args.state):
    parser.error(f"state {args.state!r} is not available for alternative {args.alternative!r}")
print("\n".join(make(args.alternative, args.width, args.height, args.state)))
