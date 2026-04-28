<div>

[**简体中文**](README_zh_CN.md)

</div>

# FlClash

[![Downloads](https://img.shields.io/github/downloads/makriq3/FlClash/total?style=flat-square&logo=github)](https://github.com/makriq3/FlClash/releases/)[![Last Version](https://img.shields.io/github/release/makriq3/FlClash/all.svg?style=flat-square)](https://github.com/makriq3/FlClash/releases/)[![License](https://img.shields.io/github/license/makriq3/FlClash?style=flat-square)](LICENSE)

Независимая линия FlClash, которую поддерживает `makriq3`. Основной фокус: защита Android VPN, более простой механизм обновлений и полностью самостоятельный контур выпуска внутри этого репозитория.

## Фокус продукта

- Android VPN-режим дополнительно защищён от localhost-утечек через локальные прокси.
- Усиление защиты Android применяется не только при старте, но и во время обновления конфигурации на лету.
- Проверка Android-релизов строится вокруг GitHub Actions, а не вокруг бесконечных ручных переустановок APK.
- Исследования, ограничения и принятые меры хранятся прямо в репозитории.

## Текущие приоритеты

1. Сократить видимую для приложений Android-поверхность утечек без требования root.
2. Держать репозиторий самодостаточным и полностью релизопригодным из этого форка.
3. Построить стабильную основу для следующих улучшений приватности и пользовательского опыта.

## Документация и безопасность

- [Исследование защиты Android VPN](docs/android-vpn-hardening.md)
- [Политика безопасности](SECURITY.md)
- [План развития](ROADMAP.md)
- [Журнал изменений](CHANGELOG.md)

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

## Что уже сделано для защиты Android

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

## Направление развития

Этот репозиторий развивается как самостоятельная релизная линия со своими:

- правилами усиления приватности Android,
- идентификаторами приложения и packaging metadata,
- конвейером релизов,
- документацией по безопасности,
- и собственной дорожной картой.
