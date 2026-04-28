#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


FORBIDDEN_FIRST_WORDS = {
    "адаптировать",
    "включить",
    "влить",
    "восстановить",
    "добавить",
    "доработать",
    "заменить",
    "изменить",
    "инициализировать",
    "исправить",
    "обновить",
    "откатить",
    "переделать",
    "переименовать",
    "переопределить",
    "переписать",
    "перестать",
    "перестроить",
    "подправить",
    "преобразовать",
    "принудительно",
    "разделить",
    "рандомизировать",
    "сделать",
    "синхронизировать",
    "скрывать",
    "собрать",
    "создать",
    "сохранять",
    "не",
    "удалить",
    "удерживать",
    "улучшить",
    "установить",
}

FORBIDDEN_PATTERNS = [
    re.compile(r"^обновить\s+changelog(?:\.md)?$", re.IGNORECASE),
    re.compile(r"^обновлено:\s*changelog(?:\.md)?$", re.IGNORECASE),
    re.compile(r"^обновить\s+change\.yaml$", re.IGNORECASE),
    re.compile(r"^обновлено:\s*change\.yaml$", re.IGNORECASE),
    re.compile(r"^доработаны(?:\s+\S+)?\s+детали$", re.IGNORECASE),
    re.compile(r"^исправлен\s+ряд\s+(?:проблем|ошибок)$", re.IGNORECASE),
    re.compile(r"^исправлено:\s*ряд\s+(?:проблем|ошибок)$", re.IGNORECASE),
]

FORBIDDEN_SECTION_TITLES = {
    "верификация",
    "проверка",
    "проверки",
    "ci",
    "downloads",
    "assets",
    "checksums",
    "технические детали",
    "для разработчиков",
    "подробности",
}

FORBIDDEN_CONTENT_PATTERNS = [
    re.compile(r"`[^`]+`"),
    re.compile(r"github actions", re.IGNORECASE),
    re.compile(r"\bworkflow\b", re.IGNORECASE),
    re.compile(r"\bpipeline\b", re.IGNORECASE),
    re.compile(r"\bflutter analyze\b", re.IGNORECASE),
    re.compile(r"\bflutter test\b", re.IGNORECASE),
    re.compile(r"\bsha256\b", re.IGNORECASE),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate release note wording in CHANGELOG.md",
    )
    parser.add_argument("--tag", required=True, help="Release tag, for example v0.8.98")
    parser.add_argument(
        "--changelog",
        default="CHANGELOG.md",
        help="Path to CHANGELOG.md relative to the repository root",
    )
    return parser.parse_args()


def extract_tag_lines(lines: list[str], tag: str) -> tuple[int, list[tuple[int, str]]]:
    start = None
    tag_header = f"## {tag}"
    for index, line in enumerate(lines):
        if line.strip() == tag_header:
            start = index
            break
    if start is None:
        raise SystemExit(f"Не удалось найти секцию {tag} в CHANGELOG.md")

    result: list[tuple[int, str]] = []
    for offset, line in enumerate(lines[start + 1 :], start + 2):
        if line.startswith("## "):
            break
        result.append((offset, line))
    return start + 1, result


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())


def normalize_heading(text: str) -> str:
    return normalize(text).strip(":").casefold()


def validate_block(lines: list[tuple[int, str]]) -> list[str]:
    errors: list[str] = []
    bullet_count = 0

    for line_no, raw_line in lines:
        heading_match = re.match(r"^\s{0,3}#{3,6}\s+(.*\S)\s*$", raw_line)
        if heading_match is not None:
            heading = normalize_heading(heading_match.group(1))
            if heading in FORBIDDEN_SECTION_TITLES:
                errors.append(
                    f"{line_no}: служебный или технический подзаголовок не должен попадать в пользовательский changelog: `{heading_match.group(1).strip()}`",
                )
            continue

        bullet_match = re.match(r"^\s*-\s+(.*\S)\s*$", raw_line)
        if bullet_match is None:
            if raw_line.strip():
                errors.append(
                    f"{line_no}: в секции релиза допустимы только bullet-пункты без служебных абзацев: `{raw_line.strip()}`",
                )
            continue

        bullet_count += 1
        text = normalize(bullet_match.group(1))

        if any(pattern.match(text) for pattern in FORBIDDEN_PATTERNS):
            errors.append(
                f"{line_no}: слишком расплывчатая или служебная формулировка: `{text}`",
            )
            continue

        for pattern in FORBIDDEN_CONTENT_PATTERNS:
            if pattern.search(text):
                errors.append(
                    f"{line_no}: пользовательский changelog не должен содержать служебные или технические маркеры: `{text}`",
                )
                break
        else:
            first_word_match = re.match(r"^([A-Za-zА-Яа-я-]+)", text)
            if first_word_match is None:
                continue

            first_word = first_word_match.group(1).casefold()
            if first_word in FORBIDDEN_FIRST_WORDS:
                errors.append(
                    f"{line_no}: todo-формулировка в инфинитиве: `{text}`",
                )

    if bullet_count == 0:
        errors.append("В релизной секции нет ни одного bullet-пункта.")

    return errors


def main() -> None:
    args = parse_args()
    changelog_path = Path(args.changelog)
    lines = changelog_path.read_text(encoding="utf-8").splitlines()
    _, tag_lines = extract_tag_lines(lines, args.tag)
    errors = validate_block(tag_lines)

    if errors:
        print(f"Секция {args.tag} не прошла проверку release notes:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        raise SystemExit(1)

    print(f"Секция {args.tag} прошла проверку release notes.")


if __name__ == "__main__":
    main()
