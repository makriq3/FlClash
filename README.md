# FlClash

[![Downloads](https://img.shields.io/github/downloads/makriq-org/FlClash/total?style=flat-square&logo=github)](https://github.com/makriq-org/FlClash/releases/)
[![Latest Release](https://img.shields.io/github/release/makriq-org/FlClash/all.svg?style=flat-square)](https://github.com/makriq-org/FlClash/releases/)
[![License](https://img.shields.io/github/license/makriq-org/FlClash?style=flat-square)](LICENSE)

Независимый форк FlClash с упором на Android, приватность и аккуратные автономные релизы.

> Основной язык публичной документации этого репозитория — русский.

## Что это за проект

FlClash — кроссплатформенный Clash-совместимый клиент для Android, Windows, macOS и Linux. Этот форк развивается независимо от апстрима и служит отдельным продуктовым репозиторием: здесь живут исходники, релизы, документация и правила сопровождения.

## Зачем нужен этот форк

Форк решает две практические задачи:

- развивать Android-направление быстрее и аккуратнее, чем это возможно в апстриме;
- выпускать понятные и воспроизводимые релизы прямо из этого репозитория.

Текущий фокус:

- усиление приватности Android VPN-режима;
- profile-driven split tunneling на Android;
- понятные release notes без технического мусора;
- прозрачный и предсказуемый релизный процесс.

## Ключевые возможности

- Поддержка Android, Windows, macOS и Linux
- Clash-совместимые профили и подписки
- WebDAV-синхронизация
- Самообновление Android-сборок
- Android split tunneling из YAML-профиля
- Дополнительное усиление Android VPN по умолчанию

## Что важно понимать про Android-приватность

Этот форк уменьшает практические client-side утечки в Android VPN-режиме: закрывает лишние localhost listeners, убирает лишнюю публикацию локального proxy в систему и делает поведение Android-пайплайна более безопасным по умолчанию.

При этом проект **не обещает** «полную невидимость VPN». Публичные Android API по-прежнему могут показывать часть VPN-сигналов, и это уже не решается только клиентом без root/Xposed-подобного слоя.

Подробности:

- [Исследование защиты Android VPN](docs/android-vpn-hardening.md)
- [Раздельное туннелирование Android через профиль](docs/android-profile-split-tunneling.md)
- [Политика безопасности](SECURITY.md)

## Документация

- [Правила ведения репозитория](CONTRIBUTING.md)
- [Процесс релизов](docs/releasing.md)
- [Краткий changelog для пользователей](CHANGELOG.md)
- [Технические release notes](docs/releases/README.md)
- [План развития](ROADMAP.md)

## Скриншоты

### Desktop

<p align="center">
  <img alt="desktop" src="snapshots/desktop.gif">
</p>

### Mobile

<p align="center">
  <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Сборка

1. Инициализируйте submodules:

```bash
git submodule update --init --recursive
```

2. Установите `Flutter` и `Go`.
3. Для Android-сборки установите `Android SDK` и `Android NDK`.
4. Подготовьте нужную платформу:

```bash
dart setup.dart android
dart setup.dart windows --arch amd64
dart setup.dart linux --arch amd64
dart setup.dart macos --arch arm64
```

## Модель релизов

- `main` хранит только то, что уже прошло предрелизную обкатку.
- Каждый релиз готовится в отдельной ветке `release/vX.Y.Z`.
- Предрелизы публикуются тегами `vX.Y.Z-preN` прямо из release-ветки.
- После проверки release-ветка мержится в `main`, и только потом выпускается стабильный тег `vX.Y.Z`.
- Короткий текст релиза берётся из верхней секции [`CHANGELOG.md`](CHANGELOG.md).
- Подробная техничка живёт в [`docs/releases`](docs/releases/README.md).

## Совместимость со старой структурой

Файл [README_zh_CN.md](README_zh_CN.md) оставлен только как совместимый указатель на основную русскоязычную документацию.
