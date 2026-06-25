#!/usr/bin/env python3
"""Extract notification preview text by sentence count."""

from __future__ import annotations

import re
import sys


def split_sentences(text: str) -> list[str]:
    text = text.strip()
    if not text:
        return []
    parts = re.split(r"(?<=[.!?])\s+", text)
    return [part.strip() for part in parts if part.strip()]


def preview_text(text: str, mode: str) -> str:
    text = text.strip()
    if not text:
        return ""

    sentences = split_sentences(text)
    if mode == "two":
        if len(sentences) >= 2:
            return f"{sentences[0]} {sentences[1]}"
        if len(sentences) == 1:
            return sentences[0]
        return text[:160]

    if mode == "full":
        return text[:200]

    if sentences:
        return sentences[0]
    return text[:80]


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "sentence"
    raw = sys.stdin.read()
    print(preview_text(raw, mode))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
