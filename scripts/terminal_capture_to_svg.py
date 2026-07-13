#!/usr/bin/env python3
import html
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
title = sys.argv[3]
lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
cols = max([len(line) for line in lines] + [1])
cell_w, cell_h, pad = 8, 17, 18
width, height = cols * cell_w + pad * 2, len(lines) * cell_h + pad * 2 + 24
body = []
for index, line in enumerate(lines):
    escaped = html.escape(line.rstrip())
    body.append(f'<text x="{pad}" y="{pad + 38 + index * cell_h}" xml:space="preserve">{escaped}</text>')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<rect width="100%" height="100%" rx="10" fill="#1e1e1e"/>
<rect width="100%" height="30" rx="10" fill="#252526"/>
<circle cx="16" cy="15" r="5" fill="#ff5f56"/><circle cx="32" cy="15" r="5" fill="#ffbd2e"/><circle cx="48" cy="15" r="5" fill="#27c93f"/>
<text x="64" y="20" fill="#d4d4d4" font-family="sans-serif" font-size="13">{html.escape(title)}</text>
<g fill="#d4d4d4" font-family="monospace" font-size="14">{''.join(body)}</g>
</svg>'''
target.write_text(svg, encoding="utf-8")
