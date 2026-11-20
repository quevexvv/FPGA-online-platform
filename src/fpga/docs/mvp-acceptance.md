# Приёмка локального MVP

## Как повторить

Из `src/fpga` выполните `make all`. Для аппаратного прогона подготовьте
USB-Blaster, UART, пользовательский systemd и копию
[конфигурации стенда](../config/integration.example.json). Укажите её
абсолютный путь в `FPGA_RUN_CONFIG` и проверьте цепочку через `jtagconfig`.
Рабочий каталог создавайте на разделе с [достаточным резервом](pilot-limits.md).

```bash
export FPGA_JOBS_ROOT
FPGA_JOBS_ROOT=$(mktemp -d "$PWD/build/acceptance.XXXXXXXX")
mkdir -m 700 "$FPGA_JOBS_ROOT/incoming"
read -r run_id < /proc/sys/kernel/random/uuid
upload="$FPGA_JOBS_ROOT/incoming/$run_id"
mkdir -p "$upload/src"
jq --arg id "$run_id" \
  '.run_id=$id | .kind="combinational" | .test_set="combinational-v1"' \
  examples/manifest.json > "$upload/manifest.json"
cp examples/combinational/student_top.v "$upload/src/student_top.v"
bin/fpga-dispatch submit --run-id "$run_id" --mode hardware
bin/fpga-dispatch status --run-id "$run_id"
```

При одном кабеле подключите UART после успешной загрузки в SRAM. Начало
ожидания видно по появлению `output/logs/uart.log`. Для проверки несовпадения
подготовьте новый ID и в копии исходника замените присваивание `dout` на
`assign dout = 18'h00000;`. Для проверки отсутствующего UART оставьте кабель
в USB-Blaster после прошивки. Для отдельного прогона Counter используйте
`examples/counter/student_top.v` и поля манифеста по умолчанию.

После `finished` прочитайте `output/result.json` и сохраните результат
и необходимые логи. Повторите `submit` с тем же ID и режимом, ожидая
`existing`. Затем вызовите `cleanup` и убедитесь, что повторный `cleanup`
возвращает ту же отметку `cleaned`. Для каждого нового исполнения нужен
новый ID.

## Результаты

| Сценарий | Итог | Подтверждение |
|---|---|---|
| Counter на C5G | `passed`, 1 из 1, `hardware_verified=true` | При `din=0x001` после 3 тактов получено `0x00003`. Результат виден в полном отчёте на сайте |
| Комбинационная схема на C5G | `passed`, 1 из 1, `hardware_verified=true` | При `din=0x2aa` и `steps=0` получено ожидаемое `0x002aa` |
| Комбинационная схема с постоянным нулём на C5G | `mismatch`, 0 из 1, `hardware_verified=true` | При `din=0x2aa` получено `0x00000` вместо `0x002aa` |
| UART отключён после загрузки | `board_error/uart_not_ready`, `hardware_verified=false` | Программатор завершился успешно, устройство UART не появилось |
| Занятый стенд | `busy/stand_busy`, `hardware_verified=false` | Параллельная попытка из другого каталога заданий закончилась до Quartus |
| Синтаксическая ошибка HDL | `invalid_input/hdl_invalid`, `hardware_verified=false` | Диспетчер зарегистрировал терминальный результат |
| Counter в mock | `passed`, 1 из 1, `hardware_verified=false` | Выполнен через диспетчер и пользовательский systemd |

На завершённых тестовых запусках проверены повторный `submit`, удаление
данных после сохранения результата и идемпотентность `cleanup`. Порядок
публикации `starting` до `accepted` и `result.json` до `finished`,
а также сохранение снимков при обрыве UART проверены тестами с заглушками
и псевдотерминалом. Тест скрипта UART воспроизводит задержку выдачи прав
после появления устройства.
