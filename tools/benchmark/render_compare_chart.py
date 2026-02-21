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


def short_label(s: str, max_len: int = 24) -> str:
    if len(s) <= max_len:
        return s
    return s[: max_len - 3] + "..."


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
    gap = 12 if n > 1 else 0
    bar_w = max(20, int((inner_w - gap * (n - 1)) / n))

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
            f'<text x="{x + bar_w / 2:.1f}" y="{bottom + 14}" text-anchor="middle" font-size="11" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#374151">{esc(short_label(c["label"]))}</text>'
        )
    return "\n".join(lines)


def choose_layout(layout: str, max_width: int) -> str:
    if layout != "auto":
        return layout
    if 0 < max_width < 1100:
        return "vertical"
    return "horizontal"


def size_for_layout(layout: str):
    if layout == "vertical":
        return 920, 760
    return 1200, 440


def maybe_scale(width: int, height: int, max_width: int):
    if max_width <= 0 or width <= max_width:
        return width, height
    ratio = max_width / width
    return int(round(width * ratio)), int(round(height * ratio))


def panel_geometry(layout: str, width: int, height: int):
    outer = 24
    top = 76
    if layout == "vertical":
        gap = 18
        panel_w = width - outer * 2
        panel_h = int((height - top - outer - gap) / 2)
        return (
            (outer, top, panel_w, panel_h),
            (outer, top + panel_h + gap, panel_w, panel_h),
        )

    gap = 32
    panel_w = int((width - outer * 2 - gap) / 2)
    panel_h = height - top - 34
    return (
        (outer, top, panel_w, panel_h),
        (outer + panel_w + gap, top, panel_w, panel_h),
    )


def render_svg(cases, title: str, layout: str, max_width: int):
    selected_layout = choose_layout(layout, max_width)
    base_w, base_h = size_for_layout(selected_layout)
    width, height = maybe_scale(base_w, base_h, max_width)
    (p1x, p1y, p1w, p1h), (p2x, p2y, p2w, p2h) = panel_geometry(
        selected_layout, width, height
    )

    lines = []
    lines.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
    )
    lines.append(f'<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>')
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
            x0=p1x,
            y0=p1y,
            w=p1w,
            h=p1h,
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
            x0=p2x,
            y0=p2y,
            w=p2w,
            h=p2h,
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
    parser.add_argument(
        "--layout",
        choices=["auto", "horizontal", "vertical"],
        default="auto",
        help="chart layout (default: auto)",
    )
    parser.add_argument(
        "--max-width",
        type=int,
        default=0,
        help="limit output width in pixels, 0 disables resize (default: 0)",
    )
    args = parser.parse_args()

    text = Path(args.input).read_text(encoding="utf-8")
    cases = parse_cases(text)
    if len(cases) == 0:
        raise SystemExit("no benchmark cases found in input")

    svg = render_svg(cases, args.title, args.layout, args.max_width)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg, encoding="utf-8")
    print(f"wrote: {out}")


if __name__ == "__main__":
    main()
