# Демо счётчика на C5G и восстановление стенда

Для аппаратного демо нужны C5G, USB-Blaster, FT232R, пользовательский
systemd и Quartus Prime Lite 23.1std.0 Build 991. Используйте конфигурацию
для демо, созданную по [шаблону](../config/integration.example.json).
Там задаются абсолютные пути `quartus_sh`, `quartus_pgm`, `uart_device`, имя
кабеля и индекс устройства из `jtagconfig`. Для UART удобна стабильная
ссылка из `/dev/serial/by-id/`. Измерения и назначенные пределы приведены в
[лимитах пилота](pilot-limits.md). Штатные пределы сборки, прошивки и
готовности UART — 120, 20 и 120 секунд соответственно.

## Запуск

Выполняйте команды из `src/fpga` под учётной записью стенда, когда стенд
свободен. После включения подключите USB-Blaster и UART, затем проверьте
цепочку через `jtagconfig` и доступ на чтение и запись к порту UART.

```bash
make all
unset FPGA_DISPATCH_LAUNCH
export FPGA_RUN_CONFIG=/absolute/path/to/demo-stand.json
export FPGA_JOBS_ROOT
FPGA_JOBS_ROOT=$(mktemp -d "$PWD/build/demo.XXXXXXXX")
mkdir -m 700 -- "$FPGA_JOBS_ROOT/incoming"
run_id=$(bash scripts/demo-submit.sh hardware | jq -er '.run_id')
bin/fpga-dispatch status --run-id "$run_id"
```

С одним кабелем переключите его на UART, когда появится
`runs/<run_id>/output/logs/uart.log`. Дождитесь `state=finished`, проверяя
`status` с тем же ID. После завершения прочитайте `result.json` из `output`.
Штатный результат — `passed`, `hardware_verified=true` и `dout=0x00003`
после трёх тактов при `din=0x001`. Это соответствует LEDR0 и LEDR1 в
[логическом представлении](display-observations.md).

Для демонстрации без платы запустите `bash scripts/demo-submit.sh mock`.
У неё свой ID, `mode=mock` и `hardware_verified=false`.

## Диагностика и следующий запуск

| Сценарий | Действие и ожидаемый результат |
|---|---|
| Ошибка HDL | `bash scripts/demo-submit.sh invalid-hdl` регистрирует `invalid_input/hdl_invalid` до Quartus. |
| Ошибка готовности UART | В отдельной копии конфигурации демо задайте `uart_device` как отсутствующий путь в каталоге демо и `uart_ready_timeout_ms` как `2000`. Вызовите `FPGA_RUN_CONFIG=/absolute/path/to/timeout-stand.json bash scripts/demo-submit.sh hardware`. После прошивки ожидается `board_error/uart_not_ready`. Для демонстрации ошибки без платы используйте `mock-uart-timeout`, который возвращает `mock_uart_timeout`. |
| Прерывание исполнителя | Запустите отдельное задание `hardware` через helper. На стадии `building` остановите только его сервис командой `systemctl --user stop "fpga-run-$run_id.service"`, подставив ID этого задания. Повторите `status` с прежним ID. Ожидается `internal_error/interrupted`, а повтор `submit` с тем же режимом и ID возвращает `existing`. |

Смотрите `.error` и `.logs` в отчёте. При проблеме с запуском сервиса
используйте `journalctl --user -u "fpga-run-$run_id.service"`. Дождитесь
завершения задания перед переподключением USB. Если JTAG пропал, верните
кабель USB-Blaster и проверьте `timeout 15s jtagconfig`. Если USB-Blaster
виден в `lsusb`, а `jtagconfig` не отвечает, завершите зависший
пользовательский `jtagd` под блокировкой стенда. Следующий вызов
`jtagconfig` поднимет его снова.

```bash
(
    set -e
    source scripts/stand-lock.sh
    open_hardware_stand_lock
    flock -n -E 75 "$stand_lock"
    jtag_pid=$(pgrep -u "$(id -u)" -x jtagd)
    [[ $jtag_pid =~ ^[0-9]+$ ]]
    kill -TERM "$jtag_pid"
    for _ in {1..20}; do
        if ! kill -0 "$jtag_pid" 2>/dev/null; then
            timeout 15s jtagconfig
            exit
        fi
        sleep .1
    done
    echo 'jtagd did not exit' >&2
    exit 1
)
```

Когда JTAG и UART снова доступны, запустите `bash scripts/demo-submit.sh
hardware` со штатной конфигурацией. Скрипт зарегистрирует свежий ID.
Успешный результат подтверждает восстановление после сбоя.

При необходимости сохраните `output/result.json` и логи из `output/logs/`.
Для удаления данных завершённого демо вызовите `bin/fpga-dispatch cleanup
--run-id "$run_id"`. Повторная команда должна вернуть ту же отметку `cleaned`.

## Результаты проверки

Аппаратное демо вернуло `passed`, `hardware_verified=true` и `dout=0x00003`
в штатном запуске, после остановки исполнителя и после переподключения USB.
После переподключения `jtagconfig` завис на подключении к `jtagd`, а
перезапуск пользовательского `jtagd` под блокировкой восстановил цепочку.

Проверены коды `internal_error/interrupted`, `board_error/uart_not_ready`
и `invalid_input/hdl_invalid`. Mock вернул `passed` с
`hardware_verified=false`. Повторный submit вернул `existing`, повторный
cleanup сохранил отметку `cleaned`.
