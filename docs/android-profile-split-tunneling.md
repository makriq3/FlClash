# Раздельное туннелирование Android через профиль

Этот форк умеет читать Android split tunneling по приложениям прямо из профиля и передавать его в системный `VpnService`.

## Что поддерживается

- `tun.exclude-package`
  Эти приложения полностью обходят VPN, независимо от доменов, IP-адресов и правил маршрутизации. Внутри списка можно смешивать точные имена пакетов, маски, regex и исключения.
- `tun.include-package`
  Через VPN идут только перечисленные приложения. Все остальные Android-приложения обходят VPN. Синтаксис правил такой же: exact, mask, regex, `!`-исключения.
- `tun.exclude-package-file`
  Один путь или список путей к файлам со списками пакетов для исключения из VPN.
- `tun.include-package-file`
  Один путь или список путей к файлам со списками пакетов для whitelist-режима.
- `tun.exclude-package-url`
  Одна ссылка или список ссылок на удалённые списки пакетов для исключения из VPN.
- `tun.include-package-url`
  Одна ссылка или список ссылок на удалённые списки пакетов для whitelist-режима.

Эти поля читаются из итогового профиля перед запуском Android VPN и имеют приоритет над app-side списком приложений, настроенным вручную в интерфейсе. Если профиль задаёт split tunneling, отдельное ручное включение access control в настройках приложения больше не требуется.

## Что писать в профиле

### Исключить приложения из VPN

```yaml
tun:
  enable: true
  stack: system
  exclude-package:
    - org.telegram.messenger
    - com.android.chrome
```

Результат:

- `org.telegram.messenger` и `com.android.chrome` всегда идут мимо VPN;
- остальные приложения продолжают идти через VPN как обычно.

### Использовать маски, regex и исключения

```yaml
tun:
  enable: true
  stack: system
  exclude-package:
    - "*.yandex.*"
    - "!ru.yandex.browser"
    - re:^org\.mozilla\..+$
    - org.telegram.messenger
```

Результат:

- все установленные приложения, подходящие под `*.yandex.*`, обходят VPN;
- `ru.yandex.browser` возвращается обратно в туннель из-за правила с `!`;
- все установленные пакеты, подходящие под `re:^org\.mozilla\..+$`, тоже идут напрямую;
- `org.telegram.messenger` исключается по точному совпадению.

Поддерживаемый синтаксис одного списка:

- `com.termux` — точное имя пакета;
- `*.yandex.*` — маска, где `*` означает любую последовательность символов;
- `re:^org\.mozilla\..+$` — регулярное выражение;
- `!ru.yandex.browser` или `!re:^ru\.yandex\.browser$` — исключение из уже совпавших правил.

Правила применяются сверху вниз. Если пакет совпал с несколькими строками, побеждает последнее совпавшее правило.

### Пустить через VPN только выбранные приложения

```yaml
tun:
  enable: true
  stack: system
  include-package:
    - com.termux
    - org.mozilla.firefox
```

Результат:

- через VPN идут только `com.termux` и `org.mozilla.firefox`;
- остальные приложения обходят VPN.

### Подключить список пакетов из файла

```yaml
tun:
  enable: true
  exclude-package-file:
    - lists/android-bypass.txt
    - /storage/emulated/0/FlClash/more-bypass.txt
```

Поддерживаются:

- один путь строкой;
- YAML-список путей;
- descriptor-формат с `path` / `url`;
- относительные пути от каталога профилей FlClash;
- абсолютные пути.

### Подключить список пакетов по ссылке

```yaml
tun:
  enable: true
  exclude-package-url:
    - https://raw.githubusercontent.com/example/repo/main/android-bypass.txt
```

Или через descriptor, если нужен явный cache path:

```yaml
tun:
  enable: true
  include-package-file:
    - url: https://raw.githubusercontent.com/example/repo/main/android-vpn.yaml
      path: lists/android-vpn.yaml
```

Удалённые списки кешируются в каталоге профиля. Если источник временно недоступен, FlClash использует последнюю успешно скачанную копию.

Файл со списком пакетов может быть в одном из двух форматов.

Обычный текст:

```text
# один пакет на строку
org.telegram.messenger
*.yandex.*
!ru.yandex.browser
```

Или YAML-список:

```yaml
- org.telegram.messenger
- "*.yandex.*"
- "!ru.yandex.browser"
```

Содержимое файлов автоматически подмешивается в `tun.include-package` или `tun.exclude-package`, а сами поля `*-package-file` используются только клиентом FlClash.

## Ограничения и правила

- Используй только один режим: либо `tun.include-package` / `tun.include-package-file` / `tun.include-package-url`, либо `tun.exclude-package` / `tun.exclude-package-file` / `tun.exclude-package-url`.
- Если одновременно заданы include- и exclude-режимы, FlClash отклонит такой профиль как конфликтный.
- Эти поля применяются только в Android VPN-режиме.
- Это split tunneling по приложениям, а не по адресам: если приложение исключено из VPN, весь его трафик идет мимо VPN.
- Маски, regex и `!`-исключения раскрываются клиентом FlClash в точные package names по списку реально установленных Android-приложений перед запуском `VpnService`.
- Если какое-то правило не совпало ни с одним установленным приложением, FlClash просто пропустит его и запишет предупреждение в лог.
- FlClash не показывает отдельные окна перед попыткой получить список установленных приложений. Если доступ к списку приложений недоступен, профиль всё равно поднимется, но mask/regex-правила будут временно пропущены, а точные package names продолжат работать.

## Что не требуется

Для этого режима не нужно настраивать `allowBypass`. В этом форке `allowBypass` всё равно принудительно отключается в hardened Android VPN-режиме и не используется как основной механизм profile-driven split tunneling.
