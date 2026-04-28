<div>

[**简体中文**](README_zh_CN.md)

</div>

# FlClash

[![Downloads](https://img.shields.io/github/downloads/makriq-org/FlClash/total?style=flat-square&logo=github)](https://github.com/makriq-org/FlClash/releases/)[![Last Version](https://img.shields.io/github/release/makriq-org/FlClash/all.svg?style=flat-square)](https://github.com/makriq-org/FlClash/releases/)[![License](https://img.shields.io/github/license/makriq-org/FlClash?style=flat-square)](LICENSE)

Независимая продуктовая линия FlClash, которую сопровождает `makriq`. Репозиторий собран как самостоятельный источник правды для продукта, документации и релизов без зависимости на инфраструктуру апстрима.

## Что здесь поддерживается

- самостоятельные мультиплатформенные релизы из этого репозитория;
- Android-ориентированный контур приватности и защиты VPN;
- документация по ограничениям, безопасности и операционному процессу;
- предсказуемый release flow без ручной сборки changelog на лету.

## Принципы сопровождения

- `main` остаётся основной веткой продукта.
- Стабильные релизы публикуются тегами `v*`, а предрелизы выпускаются отдельными `v*-pre*` тегами.
- Release notes собираются из верхней секции `CHANGELOG.md`, без автокоммитов шума обратно в репозиторий.
- Веточные Android-артефакты доступны отдельно через GitHub Actions.

## Документация

- [Исследование защиты Android VPN](docs/android-vpn-hardening.md)
- [Политика безопасности](SECURITY.md)
- [План развития](ROADMAP.md)
- [Журнал изменений](CHANGELOG.md)
- [Процесс релизов](docs/releasing.md)

## Скриншоты

Десктоп:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

Мобильная версия:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Ключевые особенности

- Поддержка нескольких платформ: Android, Windows, macOS, Linux
- Flutter-интерфейс с Clash-совместимым рабочим сценарием
- Синхронизация через WebDAV
- Поддержка подписок
- Дополнительное усиление защиты Android VPN для чувствительных к приватности сценариев

## Что уже сделано для Android VPN

В Android VPN-режиме этот форк теперь закрывает такие клиентские пути утечки, как:

- локальные `mixed` / `socks` / `http` listeners,
- доступный с localhost `external-controller`,
- публикация Android system proxy,
- стабильные, легко узнаваемые параметры туннеля.

Текущая модель усиления защиты также восстанавливает корректную доменную маршрутизацию на усиленном TUN-пути, поэтому правила прямой маршрутизации Android продолжают работать без повторного открытия исходной localhost-утечки.

Важно: этот форк уменьшает то, что клиент раскрывает сам по себе. Он не заявляет о полном сокрытии VPN от публичных Android API без root/Xposed.

## Сборка

1. Обновите submodules

   ```bash
   git submodule update --init --recursive
   ```

2. Установите `Flutter` и `Go`

3. Для Android-сборок установите `Android SDK` и `Android NDK`

4. Соберите нужную платформу:

   ```bash
   dart setup.dart android
   dart setup.dart windows --arch amd64
   dart setup.dart linux --arch amd64
   dart setup.dart macos --arch arm64
   ```

## Релизы

- Веточные Android-артефакты: GitHub Actions `android-веточная-сборка`
- Стабильный мультиплатформенный релиз: push тега `v*`
- Release notes и краткие обновления собираются из `CHANGELOG.md`, поэтому достаточно поддерживать в актуальном состоянии только верхнюю секцию под новый тег.
