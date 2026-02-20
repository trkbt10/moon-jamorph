#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


CASE_RE = re.compile(
    r"^\[(?P<label>[^\]]+)\]\s*$"
    r".*?^Warmup:\s*(?P<warmup>[0-9.]+)\s*$"
    r".*?^Number_of_sentences:\s*(?P<sentences>[0-9]+)\s*$"
    r".*?^Elapsed_seconds_to_tokenize_all_sentences:\s*\[(?P<min>[0-9.]+),(?P<avg>[0-9.]+),(?P<max>[0-9.]+)\]\s*$"
    r".*?^Sentences_per_second:\s*\[(?P<sps_min>[0-9.]+),(?P<sps_avg>[0-9.]+),(?P<sps_max>[0-9.]+)\]\s*$",
    re.MULTILINE | re.DOTALL,
)


def parse_cases(text: str):
    cases = []
    for m in CASE_RE.finditer(text):
        cases.append(
            {
                "label": m.group("label"),
                "warmup": float(m.group("warmup")),
                "sentences": int(m.group("sentences")),
                "elapsed_min": float(m.group("min")),
                "elapsed_avg": float(m.group("avg")),
                "elapsed_max": float(m.group("max")),
                "sps_min": float(m.group("sps_min")),
                "sps_avg": float(m.group("sps_avg")),
                "sps_max": float(m.group("sps_max")),
            }
        )
    return cases


def esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def bar_panel(
    x0: int,
    y0: int,
    w: int,
    h: int,
    title: str,
    cases,
    value_key: str,
    color: str,
    suffix: str,
    lower_is_better: bool,
):
    pad = 16
    top = y0 + 28
    left = x0 + pad
    right = x0 + w - pad
    bottom = y0 + h - pad
    inner_w = right - left
    inner_h = bottom - top
    n = max(1, len(cases))
    gap = 12
    bar_w = max(24, int((inner_w - gap * (n - 1)) / n))

    values = [c[value_key] for c in cases]
    vmax = max(values) if values else 1.0
    if vmax <= 0:
        vmax = 1.0

    lines = []
    lines.append(
        f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="12" fill="#ffffff" stroke="#d5d9e2"/>'
    )
    lines.append(
        f'<text x="{x0 + 14}" y="{y0 + 20}" font-size="14" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#111827">{esc(title)}</text>'
    )
    note = "lower is better" if lower_is_better else "higher is better"
    lines.append(
        f'<text x="{right}" y="{y0 + 20}" text-anchor="end" font-size="11" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#6b7280">{note}</text>'
    )
    lines.append(
        f'<line x1="{left}" y1="{bottom}" x2="{right}" y2="{bottom}" stroke="#d5d9e2" stroke-width="1"/>'
    )

    for i, c in enumerate(cases):
        val = c[value_key]
        bh = max(1, int((val / vmax) * (inner_h - 30)))
        x = left + i * (bar_w + gap)
        y = bottom - bh
        lines.append(
            f'<rect x="{x}" y="{y}" width="{bar_w}" height="{bh}" rx="6" fill="{color}" opacity="0.88"/>'
        )
        lines.append(
            f'<text x="{x + bar_w / 2:.1f}" y="{y - 6}" text-anchor="middle" font-size="11" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#111827">{val:.6g}{suffix}</text>'
        )
        lines.append(
            f'<text x="{x + bar_w / 2:.1f}" y="{bottom + 14}" text-anchor="middle" font-size="11" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#374151">{esc(c["label"])}</text>'
        )
    return "\n".join(lines)


def render_svg(cases, title: str):
    width = 1200
    height = 440
    lines = []
    lines.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">')
    lines.append('<rect x="0" y="0" width="1200" height="440" fill="#f8fafc"/>')
    lines.append(
        f'<text x="24" y="34" font-size="22" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#0f172a">{esc(title)}</text>'
    )
    if cases:
        sent = cases[0]["sentences"]
        lines.append(
            f'<text x="24" y="56" font-size="12" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#475569">Number_of_sentences: {sent}</text>'
        )
    lines.append(
        bar_panel(
            x0=24,
            y0=76,
            w=560,
            h=330,
            title="Elapsed_seconds_to_tokenize_all_sentences (avg)",
            cases=cases,
            value_key="elapsed_avg",
            color="#2563eb",
            suffix="s",
            lower_is_better=True,
        )
    )
    lines.append(
        bar_panel(
            x0=616,
            y0=76,
            w=560,
            h=330,
            title="Sentences_per_second (avg)",
            cases=cases,
            value_key="sps_avg",
            color="#059669",
            suffix="",
            lower_is_better=False,
        )
    )
    lines.append("</svg>")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Render benchmark comparison chart SVG from quick_compare output."
    )
    parser.add_argument("--input", required=True, help="quick_compare output text file")
    parser.add_argument("--output", required=True, help="output SVG path")
    parser.add_argument(
        "--title",
        default="micado vs MeCab benchmark (vibrato style)",
        help="chart title",
    )
    args = parser.parse_args()

    text = Path(args.input).read_text(encoding="utf-8")
    cases = parse_cases(text)
    if len(cases) == 0:
        raise SystemExit("no benchmark cases found in input")

    svg = render_svg(cases, args.title)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg, encoding="utf-8")
    print(f"wrote: {out}")


if __name__ == "__main__":
    main()
