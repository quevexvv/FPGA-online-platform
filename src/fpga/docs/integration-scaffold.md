# Шпаргалка запуска FPGA-части

Диспетчер и исполнитель пока предоставляют только справку и проверки каркаса.
Выполнение заданий, обмен UART и mock ещё не реализованы. Отдельные
доверенные HDL-эксперименты собираются и прошиваются вручную.

Для текущих проверок нужны Bash, Make, jq и ShellCheck.
Quartus и подключённая плата пока не требуются. C11-компилятор понадобится,
когда появятся C-исходники.

Команды из корня репозитория:

```sh
cd src/fpga
make all   # Синтаксис скриптов, JSON и доступность точек входа
make test  # Smoke-тесты каркаса; тесты стенда пока пропущены
make lint  # ShellCheck; проверка C после появления исходников
bin/fpga-dispatch --help
bin/fpga-run --help
```

Если `make lint` сообщает `shellcheck: command not found`, установи
ShellCheck или укажи путь к имеющемуся бинарнику:

```sh
make lint SHELLCHECK=/path/to/shellcheck
```

`config/integration.example.json` пока не используется командами;
корень заданий и UART-порт в нём не заданы. Требования аппаратного запуска
нужно дополнить после реализации исполнителя.

Дополнительные проверки: `make test-hdl` (Icarus Verilog),
`make test-contract` и `make test-protocol` (jq). Они не требуют платы/Quartus.
Протоколы экспериментов: [LED](led-check.md), [симулятор](simulation.md),
[clock в симуляции](clock-experiment.md), [clock на плате](clock-board.md).
Контракты: [файловый](file-contract.md), [UART](uart-protocol.md).
