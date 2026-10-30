# Файловый контракт v1

Все JSON в `examples/` — вымышленные примеры, не результаты измерения платы.
`make test-contract` проверяет их через jq и проверяет отказы на испорченных
данных. `scripts/contract.jq` — проверка примеров, не реализация диспетчера
и не гарантия безопасного доступа к файловой системе.

Обязательные поля перечислены в `required(...)` соответствующих правил:

| Файл | Поля |
|---|---|
| manifest | schema_version, run_id, top, kind, sources, test_set |
| status | schema_version, run_id, mode, state, stage, started_at, updated_at, finished_at, result_status |
| result | schema_version, run_id, mode, status, hardware_verified, started_at, finished_at, summary, observations, error, logs |

`run_id` — UUID в нижнем регистре; версия — 1; `mode` — hardware или mock.
Все поля обязательны, даже допускающие null. Время — UTC, logs — пути внутри
output. `test_set` — доверенное установленное имя, не путь от студента.
Предварительный HDL-интерфейс: `student_top(clk,reset,din[9:0],dout[17:0])`,
синхронный active-high reset; он может измениться до реализации обёртки.

Семь итогов: passed, mismatch, build_error, board_error, invalid_input, busy,
internal_error. Busy — терминальный результат исполнителя. Starting со stage
dispatch публикуется **до accepted**; accepted означает только регистрацию.
Running — выполнение, finished — завершение; result публикуется **до finished**.
Повтор submit того же ID возвращает existing, не запускает работу повторно.

`hardware_verified=true` означает полную аппаратную проверку в данном запуске,
включая прошивку; допустим для passed/mismatch. Для mock и неполной проверки
всегда false. Частичный аппаратный обмен даёт board_error с сохранёнными
наблюдениями. Пример mock явно сохраняет mode=mock. Сведения о прошивке,
порядке атомарных публикаций и неизменности input проверяются будущими
интеграционными тестами, а не одним JSON.
