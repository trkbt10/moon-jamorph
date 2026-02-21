#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

BEGIN_MARKER = "<!-- BENCHMARK_RESULTS_BEGIN -->"
END_MARKER = "<!-- BENCHMARK_RESULTS_END -->"

LEGACY_PATTERN = re.compile(
    r"実測結果（.*?\n\n```text\n.*?```(?:\n\n!\[micado vs MeCab vs Vibrato benchmark\]\(bench/benchmark/quick_compare_latest\.svg\)"
    r"|\n\nグラフ出力:.*|\n\nシェア向けPNG:.*\n元SVG:.*)?",
    re.DOTALL,
)


def build_block(benchmark_text: str) -> str:
    body = extract_results_only(benchmark_text)
    return (
        f"{BEGIN_MARKER}\n"
        "実測結果（`bench/benchmark/quick_compare_latest.txt` から自動更新）:\n\n"
        "```text\n"
        f"{body}\n"
        "```\n\n"
        "シェア向けPNG: `bench/benchmark/quick_compare_latest.png`（自動リサイズ・Git非追跡）\n"
        "元SVG: `bench/benchmark/quick_compare_latest.svg`（ローカル生成・Git非追跡）\n"
        f"{END_MARKER}"
    )


def extract_results_only(raw_text: str) -> str:
    lines = raw_text.rstrip("\n").splitlines()
    blocks: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("[") and line.endswith("]") and "/" in line:
            block = [line]
            i += 1
            while i < len(lines):
                cur = lines[i].rstrip()
                next_is_block = (
                    cur.strip().startswith("[")
                    and cur.strip().endswith("]")
                    and "/" in cur
                )
                if next_is_block:
                    break
                if not cur.strip():
                    i += 1
                    break
                block.append(cur)
                i += 1
            blocks.append("\n".join(block))
            continue
        i += 1

    if blocks:
        return "\n\n".join(blocks)
    return raw_text.rstrip("\n")


def replace_marked_block(readme_text: str, replacement: str) -> str:
    pattern = re.compile(
        rf"{re.escape(BEGIN_MARKER)}.*?{re.escape(END_MARKER)}",
        re.DOTALL,
    )
    if pattern.search(readme_text):
        return pattern.sub(replacement, readme_text, count=1)
    return ""


def replace_legacy_block(readme_text: str, replacement: str) -> str:
    if LEGACY_PATTERN.search(readme_text):
        return LEGACY_PATTERN.sub(replacement, readme_text, count=1)
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Update README benchmark section from quick_compare_latest.txt"
    )
    parser.add_argument("--readme", required=True, help="README path")
    parser.add_argument("--benchmark-text", required=True, help="benchmark text path")
    args = parser.parse_args()

    readme_path = Path(args.readme)
    benchmark_path = Path(args.benchmark_text)
    readme = readme_path.read_text(encoding="utf-8")
    benchmark_text = benchmark_path.read_text(encoding="utf-8")
    replacement = build_block(benchmark_text)

    updated = replace_marked_block(readme, replacement)
    if not updated:
        updated = replace_legacy_block(readme, replacement)
    if not updated:
        raise SystemExit("error: README benchmark block not found")

    if updated != readme:
        readme_path.write_text(updated, encoding="utf-8")
        print(f"updated README benchmark block: {readme_path}")
    else:
        print(f"README benchmark block already up to date: {readme_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
