# Симулятор и vendor-модель

2026-10-30: Icarus Verilog 13.0 stable (v13_0); Quartus Lite
23.1std.0 Build 991. `make test-simulator` использует `-g2001 -Wall`,
проверяет счётчик и намеренное несовпадение: положительный тест должен
завершиться с 0, отрицательный — ровно с 1. Плата не нужна.

`make probe-vendor QUARTUS_ROOTDIR="$HOME/intelFPGA_lite/23.1std/quartus"`
проверяет установленную vendor-модель, не заменяя её идеальным AND-gate.
Точка входа Cyclone V clock enable — `cyclonev_clkena` в
`eda/sim_lib/cyclonev_atoms.v`. Реализация ссылается на
`cyclonev_clkena_encrypted`; Mentor-модель в
`eda/sim_lib/mentor/cyclonev_atoms_ncrypt.v` зашифрована для MTI.
Исходники поставщика остаются в установке Quartus и не копируются в Git.

Для точного моделирования нужен совместимый ModelSim/Questa с библиотекой
Cyclone V и действующей лицензией. Ни `vsim`, ни `vlog` в PATH и в
установке Quartus не найдены. Бесплатная лицензия не проверена.
Поддержка простого RTL в Icarus не подтверждает поддержку vendor-моделей.
Фактический результат probe 2026-10-30: Icarus завершился с кодом 2,
`Unknown module type: cyclonev_clkena_encrypted`, `2 error(s) during elaboration`.
Положительный RTL-тест завершился с 0, намеренно ошибочный — с 1.

Вопросы кафедре, которые нужно передать пользователю:

1. Какая точная версия/редакция Quartus требуется для C5G и Cyclone V?
2. Обязателен ли ModelSim конкретной версии или допустим Questa FPGA Starter?
3. Допускается ли Icarus для обычных Verilog-2001 тестбенчей?
4. Предоставляется ли лицензия Questa/ModelSim и доступ к vendor-библиотекам?
5. Требуется ли gate-level симуляция с SDF, либо достаточно RTL и TimeQuest?

Ответы пока неизвестны; они не блокируют отдельную диагностику LED.
