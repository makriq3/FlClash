#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path


IGNORED_SECTION_TITLES = {
    "downloads",
    "assets",
    "checksums",
    "download info",
    "полезное",
    "загрузка",
    "артефакты",
    "контрольные суммы",
}

GENERIC_ITEM_PATTERNS = [
    re.compile(r"^обновить changelog$", re.IGNORECASE),
    re.compile(r"^update changelog$", re.IGNORECASE),
    re.compile(r"^доработать отдельные детали$", re.IGNORECASE),
    re.compile(r"^доработать дополнительные детали$", re.IGNORECASE),
    re.compile(r"^miscellaneous improvements?$", re.IGNORECASE),
]

HEADING_RE = re.compile(r"^\s{0,3}#{3,6}\s+(.*\S)\s*$")
BULLET_RE = re.compile(r"^(\s*)[-*]\s+(.*\S)\s*$")


@dataclass
class Section:
    title: str | None = None
    items: list[str] = field(default_factory=list)


def format_bullet(indent: str, item: str) -> str:
    nesting = max(len(indent.expandtabs(2)) // 2, 0)
    return f"{'  ' * nesting}- {item}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build clean GitHub release notes from CHANGELOG.md",
    )
    parser.add_argument("--tag", required=True, help="Release tag, for example v0.8.98")
    parser.add_argument(
        "--changelog",
        default="CHANGELOG.md",
        help="Path to CHANGELOG.md relative to the repository root",
    )
    parser.add_argument("--output", required=True, help="Output markdown file")
    parser.add_argument(
        "--summary-output",
        help="Optional plain-text file with a short release summary",
    )
    parser.add_argument(
        "--repo-url",
        required=True,
        help="Repository URL, for example https://github.com/makriq-org/FlClash",
    )
    return parser.parse_args()


def extract_release_block(changelog_text: str, tag: str) -> str:
    pattern = re.compile(
        rf"^##\s+{re.escape(tag)}\s*$\n?(.*?)(?=^##\s+|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(changelog_text)
    if match is None:
        raise SystemExit(f"Не удалось найти секцию {tag} в CHANGELOG.md")
    return match.group(1).strip()


def normalize_title(title: str) -> str:
    return re.sub(r"\s+", " ", title.strip().strip(":")).lower()


def is_generic_item(item: str) -> bool:
    normalized = re.sub(r"\s+", " ", item.strip())
    return any(pattern.match(normalized) for pattern in GENERIC_ITEM_PATTERNS)


def parse_sections(block: str) -> list[Section]:
    sections: list[Section] = []
    current = Section()

    def flush() -> None:
        nonlocal current
        if current.title or current.items:
            sections.append(current)
        current = Section()

    for raw_line in block.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            continue

        heading_match = HEADING_RE.match(line)
        if heading_match:
            flush()
            current.title = heading_match.group(1).strip()
            continue

        bullet_match = BULLET_RE.match(line)
        item = bullet_match.group(2).strip() if bullet_match else stripped
        if is_generic_item(item):
            continue
        current.items.append(
            item if not bullet_match else format_bullet(bullet_match.group(1), item),
        )

    flush()
    return sections


def is_ignored_section(section: Section) -> bool:
    if section.title is None:
        return False
    return normalize_title(section.title) in IGNORED_SECTION_TITLES


def build_highlights(sections: list[Section], limit: int = 4) -> list[str]:
    highlights: list[str] = []
    seen: set[str] = set()

    for section in sections:
        if is_ignored_section(section):
            continue
        for item in section.items:
            if item.startswith("  - "):
                continue
            candidate = item[2:].strip() if item.startswith("- ") else item.strip()
            candidate_key = candidate.casefold()
            if not candidate or candidate.endswith(":") or candidate_key in seen:
                continue
            highlights.append(candidate)
            seen.add(candidate_key)
            if len(highlights) >= limit:
                return highlights

    return highlights


def render_details(sections: list[Section]) -> list[str]:
    lines: list[str] = []
    for section in sections:
        if is_ignored_section(section) or not section.items:
            continue
        if section.title:
            lines.append(f"### {section.title}")
            lines.append("")
        for item in section.items:
            lines.append(item if item.lstrip().startswith("- ") else f"- {item}")
        lines.append("")
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def has_extra_details(sections: list[Section], highlights: list[str]) -> bool:
    detail_items: list[str] = []
    titled_sections = 0

    for section in sections:
        if is_ignored_section(section) or not section.items:
            continue
        if section.title:
            titled_sections += 1
        for item in section.items:
            normalized_item = item.lstrip()
            detail_items.append(
                normalized_item[2:].strip()
                if normalized_item.startswith("- ")
                else normalized_item.strip(),
            )

    if not detail_items:
        return False
    if len(detail_items) > len(highlights):
        return True
    if titled_sections > 1:
        return True
    return detail_items != highlights[: len(detail_items)]


def build_release_markdown(
    tag: str,
    repo_url: str,
    highlights: list[str],
    details: list[str],
) -> str:
    version = tag[1:] if tag.startswith("v") else tag
    lines = [f"# FlClash {version}", ""]

    if highlights:
        lines.extend(["## Главное", ""])
        lines.extend(f"- {item}" for item in highlights)
        lines.append("")

    if details:
        lines.extend(["## Подробности", ""])
        lines.extend(details)
        lines.append("")

    lines.extend(
        [
            "## Загрузка",
            "",
            "- Выберите артефакт для своей платформы в блоке Assets ниже.",
            "- Контрольные суммы `*.sha256` приложены к релизу рядом с бинарниками.",
            f"- Полная история изменений: [CHANGELOG.md]({repo_url}/blob/main/CHANGELOG.md)",
        ]
    )
    return "\n".join(lines).strip() + "\n"


def build_summary(tag: str, highlights: list[str]) -> str:
    lines = [tag]
    lines.extend(f"- {item}" for item in highlights[:4])
    return "\n".join(lines).strip() + "\n"


def main() -> None:
    args = parse_args()
    changelog_path = Path(args.changelog)
    changelog_text = changelog_path.read_text(encoding="utf-8")
    block = extract_release_block(changelog_text, args.tag)
    sections = parse_sections(block)
    highlights = build_highlights(sections)
    details = render_details(sections) if has_extra_details(sections, highlights) else []
    release_notes = build_release_markdown(args.tag, args.repo_url, highlights, details)

    output_path = Path(args.output)
    output_path.write_text(release_notes, encoding="utf-8")

    if args.summary_output:
        summary_path = Path(args.summary_output)
        summary_path.write_text(
            build_summary(args.tag, highlights),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
