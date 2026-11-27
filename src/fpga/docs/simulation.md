# Проверки без платы

Симулятор запускает HDL на компьютере. Вместо настоящих проводов и LED
тест задаёт сигналы и проверяет ответы схемы. Так можно быстро обнаружить,
например, лишний такт или неправильный результат счётчика.

Для обычного Verilog-2001 проверен Icarus Verilog 13.0:

```sh
make test-simulator
```

Команда запускает два теста. Правильный должен завершиться с кодом 0,
намеренно ошибочный — с кодом 1. Оба случая проверены: ошибки схемы
не остаются незамеченными из-за успешного завершения симулятора.

Все обычные HDL-тесты запускаются через `make test-hdl`. Плата и Quartus
для них не нужны. Эта команда также включена в CI; удалённый запуск CI
в рамках этих проверок не выполнялся.

Приём байтов служебного UART проверяется командой `make test-uart-rx`,
передача — `make test-uart-tx`.
Описание сигналов и проверок — в [UART на ПЛИС](uart-hdl.md).

## SystemVerilog

Icarus Verilog 13.0 проверяет манифест с `language=systemverilog`
в режиме `-g2012`. Quartus Prime Lite 23.1 открывает исходники `.sv`
как SystemVerilog, а `.v` и служебную обёртку как Verilog.
Поддержан синтезируемый поднабор для простого DUT с портами
`student_top`. Проверенный пример использует `logic` и `always_ff`.
Вызовы DPI, внешние файлы и конструкции вне поднабора обоих инструментов
в пилот не входят.

`make test-systemverilog` прогоняет тот же UART-тест обёртки со
[счётчиком на SystemVerilog](../examples/systemverilog/student_top.sv).
Для аппаратного запуска скопируйте [манифест версии 2](../examples/systemverilog/manifest.json)
и исходник в стандартную загрузку `incoming/<run_id>`, проставьте новый
`run_id` и вызовите `fpga-dispatch submit --run-id <run_id> --mode hardware`.
Действующий бэкенд продолжает формировать манифесты версии 1.
На C5G этот манифест через обычный `submit` вернул `passed`,
`hardware_verified=true` и `dout=0x00003`.

## VHDL-2008

[Счётчик на VHDL](../examples/vhdl/student_top.vhd) имеет те же
порты, что и Verilog DUT. На границе языков используются `std_logic`
для `clk` и `reset`, `std_logic_vector(9 downto 0)` для `din` и
`std_logic_vector(17 downto 0)` для `dout`. Внутри используются
`ieee.numeric_std`, без дополнительных библиотек и generics.

Из `src/fpga` выполните:

```bash
make test-vhdl
make all build-vhdl
```

`test-vhdl` запускает [синтез GHDL](https://ghdl.github.io/ghdl/using/Synthesis.html)
с `--std=08 --out=verilog` и затем тот же тест обёртки в Icarus.
Для этого нужны GHDL со стандартной библиотекой IEEE и Icarus.
При отсутствии IEEE генерация останавливается до запуска тестбенча.
Это функциональная проверка синтезируемого поднабора после перевода DUT.
Нативная симуляция оригинальных VHDL и Verilog в Questa остаётся отдельной
проверкой. Для [Questa Starter требуется лицензия](https://www.altera.com/products/software-tools/quartus-prime/questa).

`build-vhdl` передаёт исходный VHDL-2008 и Verilog-обёртку напрямую
в один проект Quartus Prime Lite. Для аппаратной приёмки загрузите
`build/wrapper_vhdl/wrapper_vhdl.sof` под блокировкой стенда и вызовите
`UART_PORT="$uart_device" make test-hardware`. Этот проект проверяет
доверенный счётчик. Загрузка VHDL через манифест в этот пилот не входит.

GHDL 6.0.0 и Icarus Verilog 13.0 прошли симуляцию счётчика с обёрткой.
Quartus Prime Lite 23.1 собрал оригинальный VHDL вместе с Verilog.
На C5G прошли аппаратные векторы UART и STEP, включая сброс и пачку
65535 тактов. TimeQuest подтвердил запас по всем проверенным ограничениям.
