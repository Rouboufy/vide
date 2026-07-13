#!/usr/bin/env python3
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        for key in ("href", "src"):
            if key in attrs:
                self.refs.append(attrs[key])


parser = Links()
parser.feed((ROOT / "index.html").read_text(encoding="utf-8"))
required_ids = {"main", "top", "modes", "features", "install", "support"}
assert required_ids <= parser.ids
for ref in parser.refs:
    if ref.startswith("#"):
        assert ref[1:] in parser.ids, f"missing anchor: {ref}"
        continue
    parsed = urlparse(ref)
    if parsed.scheme or ref.startswith("//"):
        continue
    path = ROOT / parsed.path
    assert path.exists(), f"missing local site asset: {ref}"

html = (ROOT / "index.html").read_text(encoding="utf-8")
for phrase in ("Normal", "IDE", "Zen", "Installation", "Platform status", "limitations"):
    assert phrase.lower() in html.lower(), f"missing site content: {phrase}"
print("Static site validated")
