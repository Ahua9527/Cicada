#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


SCREENS = ("overview", "settings", "maintenance", "menubar")
SCREEN_TITLES = {
    "overview": "控制中心 Overview",
    "settings": "控制中心 Settings",
    "maintenance": "控制中心 Maintenance",
    "menubar": "菜单栏下拉",
}
REVIEW_FOCUS = {
    "overview": "Hero 状态卡、Readiness 进度环、诊断条、版本标签及侧栏选中态",
    "settings": "连接 Tab、设置子导航、卡片数量、字段间距、按钮与内联反馈",
    "maintenance": "运行时开关、文件夹网格、SleepHold 数据卡、诊断按钮与结果条",
    "menubar": "状态卡、280pt 下拉宽度、三个导航操作、分隔线与退出按钮",
}
GRID_NAMES = {
    (0, 0): "左上",
    (0, 1): "上中",
    (0, 2): "右上",
    (1, 0): "左中",
    (1, 1): "中央",
    (1, 2): "右中",
    (2, 0): "左下",
    (2, 1): "下中",
    (2, 2): "右下",
}
BACKGROUND = (9, 9, 11)
PIXEL_THRESHOLD = 24
PASS_CHANGED_RATIO = 0.05
PASS_MEAN_DELTA = 8.0


@dataclass
class Result:
    screen: str
    verdict: str
    changed_ratio: float | None = None
    mean_delta: float | None = None
    hotspots: tuple[str, ...] = ()
    resized_from: tuple[int, int] | None = None
    observation: str | None = None
    error: str | None = None


def load_font(size: int) -> ImageFont.ImageFont:
    candidates = (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    )
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def flatten(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    background = Image.new("RGBA", rgba.size, BACKGROUND + (255,))
    return Image.alpha_composite(background, rgba).convert("RGB")


def load_rgb(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return flatten(image)


def difference_mask(app: Image.Image, design: Image.Image) -> tuple[Image.Image, float, float]:
    difference = ImageChops.difference(app, design)
    channels = difference.split()
    max_channel = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    mask = max_channel.point(lambda value: 255 if value > PIXEL_THRESHOLD else 0)
    changed_pixels = mask.histogram()[255]
    changed_ratio = changed_pixels / (app.width * app.height)
    mean_delta = sum(ImageStat.Stat(difference).mean) / 3.0
    return mask, changed_ratio, mean_delta


def find_hotspots(mask: Image.Image) -> tuple[tuple[str, ...], tuple[tuple[int, int, int, int], ...]]:
    scores: list[tuple[float, tuple[int, int, int, int], str]] = []
    for row in range(3):
        top = round(mask.height * row / 3)
        bottom = round(mask.height * (row + 1) / 3)
        for column in range(3):
            left = round(mask.width * column / 3)
            right = round(mask.width * (column + 1) / 3)
            crop = mask.crop((left, top, right, bottom))
            histogram = crop.histogram()
            ratio = histogram[255] / max(1, crop.width * crop.height)
            scores.append((ratio, (left, top, right, bottom), GRID_NAMES[(row, column)]))
    selected = [item for item in sorted(scores, reverse=True) if item[0] > 0.05][:3]
    return tuple(item[2] for item in selected), tuple(item[1] for item in selected)


def annotated_pair(app: Image.Image, design: Image.Image, boxes: tuple[tuple[int, int, int, int], ...]) -> Image.Image:
    app_marked = app.copy()
    design_marked = design.copy()
    for image in (app_marked, design_marked):
        draw = ImageDraw.Draw(image)
        line_width = max(2, round(image.width / 450))
        for box in boxes:
            draw.rectangle(box, outline=(239, 68, 68), width=line_width)

    label_height = max(36, round(app.height * 0.05))
    canvas = Image.new("RGB", (app.width * 2, app.height + label_height), (24, 24, 27))
    canvas.paste(app_marked, (0, label_height))
    canvas.paste(design_marked, (app.width, label_height))
    draw = ImageDraw.Draw(canvas)
    font = load_font(max(14, round(label_height * 0.45)))
    draw.text((16, (label_height - font.size) // 2), "App", fill=(250, 250, 250), font=font)
    draw.text((app.width + 16, (label_height - font.size) // 2), "Design", fill=(250, 250, 250), font=font)
    draw.line((app.width, 0, app.width, canvas.height), fill=(82, 82, 91), width=2)
    return canvas


def compare_screen(root: Path, screen: str) -> Result:
    app_path = root / "output" / "app" / f"{screen}.png"
    design_path = root / "output" / "design" / f"{screen}.png"
    output_path = root / "output" / "compare" / f"{screen}.png"

    missing = [str(path.relative_to(root)) for path in (app_path, design_path) if not path.is_file()]
    if missing:
        return Result(screen=screen, verdict="未执行", error="缺少 " + "、".join(missing))

    try:
        app = load_rgb(app_path)
        design = load_rgb(design_path)
    except Exception as exc:  # Pillow gives useful decoder errors here.
        return Result(screen=screen, verdict="未执行", error=f"PNG 无法读取：{exc}")

    resized_from = None
    if design.size != app.size:
        resized_from = design.size
        design = design.resize(app.size, Image.Resampling.LANCZOS)

    mask, changed_ratio, mean_delta = difference_mask(app, design)
    hotspots, boxes = find_hotspots(mask)
    verdict = "一致" if changed_ratio <= PASS_CHANGED_RATIO and mean_delta <= PASS_MEAN_DELTA else "有差异"
    observation = None
    if screen != "menubar" and app.entropy() < design.entropy() * 0.75:
        observation = "App 内容密度显著低于设计稿，疑似存在大面积未渲染或缺失区域"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    annotated_pair(app, design, boxes).save(output_path, format="PNG")
    return Result(
        screen=screen,
        verdict=verdict,
        changed_ratio=changed_ratio,
        mean_delta=mean_delta,
        hotspots=hotspots,
        resized_from=resized_from,
        observation=observation,
    )


def report_markdown(root: Path, results: list[Result]) -> str:
    missing = [result for result in results if result.error]
    lines = [
        "# Cicada 新控制中心 UI 视觉验收报告",
        "",
        f"> 生成时间：{datetime.now().astimezone().isoformat(timespec='seconds')}",
        "> 判定口径：单像素最大 RGB 差值 >24 计为差异；差异像素 ≤5% 且平均 RGB 差值 ≤8 才判为“一致”。",
    ]
    if missing:
        lines.extend(
            [
                "",
                "> **需在有 GUI 的 Mac 上执行。** 当前报告缺少完整 app 截图；请确认已登录桌面，并为 Terminal/Codex 授予“辅助功能”和“屏幕录制”权限。",
            ]
        )

    lines.extend(
        [
            "",
            "## 结论总览",
            "",
            "| 画面 | 结论 | 差异像素 | 平均 RGB 差值 | 主要热点 |",
            "| --- | --- | ---: | ---: | --- |",
        ]
    )
    for result in results:
        if result.error:
            lines.append(f"| {SCREEN_TITLES[result.screen]} | 未执行 | — | — | {result.error} |")
        else:
            hotspot_text = "、".join(result.hotspots) if result.hotspots else "无"
            lines.append(
                f"| {SCREEN_TITLES[result.screen]} | {result.verdict} | "
                f"{result.changed_ratio:.1%} | {result.mean_delta:.2f} | {hotspot_text} |"
            )

    lines.extend(["", "## 分屏检查", ""])
    for result in results:
        lines.append(f"### {SCREEN_TITLES[result.screen]}")
        lines.append("")
        if result.error:
            lines.append(f"**结论：未执行。** {result.error}。")
        else:
            hotspot_text = "、".join(result.hotspots) if result.hotspots else "未发现显著热点"
            lines.append(
                f"**结论：{result.verdict}。** 差异像素 {result.changed_ratio:.1%}，"
                f"平均 RGB 差值 {result.mean_delta:.2f}，主要集中在{hotspot_text}；"
                f"人工复核重点：{REVIEW_FOCUS[result.screen]}。"
            )
            if result.observation:
                lines.append(f"疑似差异点：{result.observation}。")
            if result.resized_from:
                lines.append(
                    f"设计稿原始像素尺寸为 {result.resized_from[0]}×{result.resized_from[1]}，"
                    "比较前已按 app 截图尺寸使用 LANCZOS 归一化。"
                )
            lines.extend(["", f"![{SCREEN_TITLES[result.screen]} 对比](output/compare/{result.screen}.png)"])
        lines.append("")

    lines.extend(
        [
            "## 疑似不一致项复核说明",
            "",
        ]
    )
    for result in results:
        if result.error:
            lines.append(f"- {SCREEN_TITLES[result.screen]}：未执行，{result.error}。")
        elif result.observation:
            lines.append(f"- {SCREEN_TITLES[result.screen]}：{result.observation}。")
        else:
            hotspot_text = "、".join(result.hotspots) if result.hotspots else "无显著热点"
            lines.append(f"- {SCREEN_TITLES[result.screen]}：主要像素热点为{hotspot_text}；重点复核{REVIEW_FOCUS[result.screen]}。")
    lines.extend(
        [
            "",
            "- 红框表示 3×3 网格中差异比例最高的区域，只定位像素热点，不替代语义判断。",
            "- 实时状态、版本号、触发器数量和诊断文案参与差异计算；这些内容变化会被保守标记为疑似差异。",
            "- HTML mockup 与 SwiftUI 的字体栅格化、系统材质和原生标题栏差异不会被自动豁免。",
            "",
            "## 本次不在对照范围",
            "",
            "- NotchDrop key 不迁移。",
            "- RecordingCard 相机预览仍为占位。",
            "- Relay 配置模型差异。",
            "- 诊断数据源不同。",
            "",
            "## 重跑",
            "",
            "```bash",
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/visual-acceptance/run-all.sh",
            "```",
            "",
            "若 GUI 自动化失败，请先在“系统设置 → 隐私与安全性”中为执行脚本的 Terminal/Codex 开启“辅助功能”和“屏幕录制”，然后重跑。",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare Cicada app and design screenshots")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--allow-missing", action="store_true", help="write a blocked report and return success when screenshots are missing")
    parser.add_argument("--allow-diff", action="store_true", help="return success even when screens differ from the design (known or intentional UI changes)")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    (root / "output" / "compare").mkdir(parents=True, exist_ok=True)
    for old_output in (root / "output" / "compare").glob("*.png"):
        old_output.unlink()

    results = [compare_screen(root, screen) for screen in SCREENS]
    report_path = root / "ACCEPTANCE_REPORT.md"
    report_path.write_text(report_markdown(root, results), encoding="utf-8")
    print(f"visual report: {report_path}")
    for result in results:
        if result.error:
            print(f"{result.screen}: missing ({result.error})")
        else:
            print(
                f"{result.screen}: {result.verdict}; changed={result.changed_ratio:.1%}; "
                f"mean_delta={result.mean_delta:.2f}; hotspots={','.join(result.hotspots) or 'none'}"
            )

    has_missing = any(result.error for result in results)
    has_diff = any(result.verdict == "有差异" for result in results)
    if has_diff and not args.allow_diff:
        print("visual acceptance failed: screens differ from design; review the report")
        return 1
    if has_missing and not args.allow_missing:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
