#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


CASE_LABEL_RE = re.compile(r"^\[(?P<label>[^\]]+)\]\s*$")
TRIPLE_RE = re.compile(r"^\[(?P<min>[0-9.]+),(?P<avg>[0-9.]+),(?P<max>[0-9.]+)\]$")


def parse_triple(value: str):
    m = TRIPLE_RE.match(value.strip())
    if not m:
        return None
    return float(m.group("min")), float(m.group("avg")), float(m.group("max"))


def parse_cases(text: str):
    lines = text.splitlines()
    cases = []
    i = 0
    while i < len(lines):
        label_match = CASE_LABEL_RE.match(lines[i].strip())
        if not label_match:
            i += 1
            continue
        label = label_match.group("label")
        i += 1
        fields = {}
        while i < len(lines):
            raw = lines[i].strip()
            if not raw:
                i += 1
                break
            if CASE_LABEL_RE.match(raw):
                break
            if ":" in raw:
                key, value = raw.split(":", 1)
                fields[key.strip()] = value.strip()
            i += 1

        try:
            warmup = float(fields["Warmup"])
            sentences = int(fields["Number_of_sentences"])
        except (KeyError, ValueError):
            continue

        elapsed = parse_triple(fields.get("Elapsed_seconds_to_tokenize_all_sentences", ""))
        sps = parse_triple(fields.get("Sentences_per_second", ""))
        if elapsed is None or sps is None:
            continue

        case = {
            "label": label,
            "warmup": warmup,
            "sentences": sentences,
            "elapsed_min": elapsed[0],
            "elapsed_avg": elapsed[1],
            "elapsed_max": elapsed[2],
            "sps_min": sps[0],
            "sps_avg": sps[1],
            "sps_max": sps[2],
        }

        elapsed_wo = parse_triple(
            fields.get("Elapsed_seconds_without_startup_estimate", "")
        )
        sps_wo = parse_triple(
            fields.get("Sentences_per_second_without_startup_estimate", "")
        )
        if elapsed_wo is not None and sps_wo is not None:
            case["elapsed_wo_startup_min"] = elapsed_wo[0]
            case["elapsed_wo_startup_avg"] = elapsed_wo[1]
            case["elapsed_wo_startup_max"] = elapsed_wo[2]
            case["sps_wo_startup_min"] = sps_wo[0]
            case["sps_wo_startup_avg"] = sps_wo[1]
            case["sps_wo_startup_max"] = sps_wo[2]

        cases.append(case)
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


def choose_layout(layout: str, max_width: int, panel_count: int) -> str:
    if layout != "auto":
        return layout
    if panel_count >= 4 and 0 < max_width < 1100:
        return "vertical"
    return "horizontal"


def size_for_layout(layout: str, panel_count: int):
    if panel_count >= 4:
        if layout == "vertical":
            return 920, 1460
        return 1200, 780
    if layout == "vertical":
        return 920, 760
    return 1200, 440


def maybe_scale(width: int, height: int, max_width: int):
    if max_width <= 0 or width <= max_width:
        return width, height
    ratio = max_width / width
    return int(round(width * ratio)), int(round(height * ratio))


def panel_geometry(layout: str, width: int, height: int, panel_count: int, top: int):
    outer = 24
    gap_x = 26
    gap_y = 20
    if layout == "vertical":
        cols = 1
    else:
        cols = 1 if panel_count == 1 else 2
    rows = (panel_count + cols - 1) // cols

    panel_w = int((width - outer * 2 - gap_x * (cols - 1)) / cols)
    panel_h = int((height - top - outer - gap_y * (rows - 1)) / rows)
    panels = []
    for idx in range(panel_count):
        row = idx // cols
        col = idx % cols
        x = outer + col * (panel_w + gap_x)
        y = top + row * (panel_h + gap_y)
        panels.append((x, y, panel_w, panel_h))
    return panels


def render_svg(cases, title: str, layout: str, max_width: int):
    has_wo_startup = all(
        "elapsed_wo_startup_avg" in c and "sps_wo_startup_avg" in c for c in cases
    )
    panels = [
        {
            "title": "Elapsed_seconds_to_tokenize_all_sentences (avg, startup-included)",
            "value_key": "elapsed_avg",
            "color": "#2563eb",
            "suffix": "s",
            "lower_is_better": True,
        },
        {
            "title": "Sentences_per_second (avg, startup-included)",
            "value_key": "sps_avg",
            "color": "#059669",
            "suffix": "",
            "lower_is_better": False,
        },
    ]
    if has_wo_startup:
        panels.extend(
            [
                {
                    "title": "Elapsed_seconds_without_startup_estimate (avg)",
                    "value_key": "elapsed_wo_startup_avg",
                    "color": "#7c3aed",
                    "suffix": "s",
                    "lower_is_better": True,
                },
                {
                    "title": "Sentences_per_second_without_startup_estimate (avg)",
                    "value_key": "sps_wo_startup_avg",
                    "color": "#d97706",
                    "suffix": "",
                    "lower_is_better": False,
                },
            ]
        )

    selected_layout = choose_layout(layout, max_width, len(panels))
    base_w, base_h = size_for_layout(selected_layout, len(panels))
    width, height = maybe_scale(base_w, base_h, max_width)
    top = 96 if has_wo_startup else 76
    panel_rects = panel_geometry(selected_layout, width, height, len(panels), top)

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
    if has_wo_startup:
        lines.append(
            '<text x="24" y="74" font-size="12" font-family="ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif" fill="#64748b">Startup-included metrics and startup-subtracted estimates are shown.</text>'
        )

    for panel, rect in zip(panels, panel_rects):
        px, py, pw, ph = rect
        lines.append(
            bar_panel(
                x0=px,
                y0=py,
                w=pw,
                h=ph,
                title=panel["title"],
                cases=cases,
                value_key=panel["value_key"],
                color=panel["color"],
                suffix=panel["suffix"],
                lower_is_better=panel["lower_is_better"],
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
