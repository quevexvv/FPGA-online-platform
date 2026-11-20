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

## Приёмка передачи результата через бэкенд

Повторный прогон использовал локальный бэкенд с отдельной SQLite.
Аппаратные попытки запускались вручную через runner, демонстрационный
пример регистрировался оператором через диспетчер. Исполнитель стартовал
через пользовательский systemd. Входной вектор комбинационной схемы —
`din=0x2aa`, `steps=0`.

| Сценарий | Результат |
|---|---|
| Штатная комбинационная схема | API вернул `passed`, `hardware_verified=true`, `dout=0x002aa`. В браузере отчёт показал «Проверено на плате» и 1 из 1 открытых тестов |
| Схема с постоянным нулём | API вернул `mismatch`, `hardware_verified=true`, `dout=0x00000`. В открытом наблюдении ожидаемое значение — `0x002aa` |
| Доверенный демонстрационный пример | API вернул `mode=mock`, `passed` и `hardware_verified=false`. В браузере отчёт показал «Без платы, не засчитывается» |
| Принудительный отказ команды сборки | API вернул `build_error`, `hardware_verified=false` |
| Принудительный отказ программатора после сборки | API вернул `board_error`, `hardware_verified=false` |

API показал `queued`, затем `running` со стадиями диспетчеризации,
сборки и прошивки, затем `finished` с результатом. На двух аппаратных
попытках повторный submit вернул `existing`. Перед очисткой сохранены
отчёты и логи по относительным путям из результата. Повторная очистка
вернула ту же отметку `cleaned`. После перезагрузки страницы отчёт о
прошедшей проверке по-прежнему открывался из истории бэкенда.

Доставка и чтение файлов проверены на общем хосте. Раздельное размещение
с SSH/SFTP требует отдельного прогона. Команды повторной проверки
приведены в [инструкции runner](../../backend/docs/fpga-runner.md) и
[проверке контракта](contract-acceptance.md).
