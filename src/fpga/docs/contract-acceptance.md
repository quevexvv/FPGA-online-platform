# Проверка контракта клиента со стендом

Клиент использует три команды `fpga-dispatch` и читает файлы из
выделенного корня заданий. Формат и правила обработки описаны в
[контракте версии 1](../../../docs/contract.md).
[Приёмка MVP на C5G](mvp-acceptance.md) содержит фактические результаты
аппаратных прогонов и шаги для их повторения.

## Проверка без платы

На Linux из `src/fpga` запустите следующий блок в Bash. Нужны `jq` и
доступный пользовательский systemd. Блок создаёт новый корень заданий
и сохраняет копию отчёта перед очисткой. Выведенный путь нужен, чтобы
посмотреть отчёт или продолжить диагностику с тем же ID.

```bash
(
    set -euo pipefail
    unset FPGA_DISPATCH_LAUNCH FPGA_RUN_CONFIG
    root=$(mktemp -d)
    export FPGA_JOBS_ROOT="$root/jobs"
    read -r id < /proc/sys/kernel/random/uuid
    printf 'Evidence: %s\nRun ID: %s\n' "$root" "$id"
    upload="$FPGA_JOBS_ROOT/incoming/$id"
    output="$FPGA_JOBS_ROOT/runs/$id/output"
    mkdir -p "$upload/src"
    jq --arg id "$id" '.run_id = $id' examples/manifest.json > "$upload/manifest.json"
    cp examples/counter/student_top.v "$upload/src/student_top.v"
    check() { jq -e --arg kind "$1" -f scripts/contract.jq "${@:2}" >/dev/null; }
    check manifest "$upload/manifest.json"

    submit() { bin/fpga-dispatch submit --run-id "$id" --mode mock; }
    status() { bin/fpga-dispatch status --run-id "$id"; }
    cleanup() { bin/fpga-dispatch cleanup --run-id "$id"; }
    submit | jq -e --arg id "$id" \
        '. == {schema_version:1,run_id:$id,disposition:"accepted"}'
    for ((attempt = 0; attempt < 30; attempt++)); do
        status > "$root/status.json"
        check status "$root/status.json"
        if jq -e '.state == "finished"' "$root/status.json" >/dev/null; then break; fi
        sleep 1
    done
    jq -e --arg id "$id" \
        '.run_id == $id and .mode == "mock" and .state == "finished" and
         .result_status == "passed"' "$root/status.json"
    check result "$output/result.json"
    jq -e --slurpfile status "$root/status.json" '
        $status[0] as $s |
        .run_id == $s.run_id and .mode == $s.mode and .status == $s.result_status and
        .started_at == $s.started_at and .finished_at == $s.finished_at and
        .hardware_verified == false and .observations[0].dout == "0x00003"
    ' "$output/result.json"
    cp "$output/result.json" "$root/result.json"

    submit | jq -e --arg id "$id" \
        '. == {schema_version:1,run_id:$id,disposition:"existing"}'
    for ((attempt = 0; attempt < 5; attempt++)); do
        if cleanup > "$root/cleaned.json"; then break; fi
        sleep 1
    done
    jq -e --arg id "$id" '. == {schema_version:1,run_id:$id,state:"cleaned"}' "$root/cleaned.json"
    cleanup | cmp "$root/cleaned.json" -
    status | cmp "$root/cleaned.json" -
    submit | jq -e '.disposition == "existing"'
    test ! -e "$output"
)
```

Короткое задание может успеть завершиться до первого опроса. Порядок
публикации `starting` перед `accepted` и результата перед `finished`
проверяется детерминированно в `tests/launch.sh` и `tests/mock.sh`.
Оба сценария входят в `make -C src/fpga test`. Там же проверяются
относительные пути логов, ошибочные JSON, аварийное восстановление
и запрет очистки активного задания.

## Подключение бэкенда

- Сопоставьте лабораторную с доверенным набором на стенде и настройте
  разрешённые индексы векторов по [инструкции runner](../../backend/docs/fpga-runner.md).
- Сохраняйте исходный `run_id` после потери ответа. Запросите его статус
  и при необходимости повторите регистрацию с тем же режимом и ID.
- После `finished` сохраняйте отчёт и нужные логи до вызова `cleanup`.
  Пути из `logs` разрешаются относительно `output` этого запуска.
- Перед показом результата сверяйте ID, режим, версию и итог.
  Для `mock` показывайте демонстрационный режим и
  `hardware_verified=false` даже при `passed`.

На общем хосте пакет публикуется в локальный `incoming`; при раздельном
размещении формат пакета и команды диспетчера сохраняются. Настройка и
проверка транспорта SSH/SFTP зависят от выбранного размещения.
