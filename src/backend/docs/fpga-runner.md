# Очередь ПЛИС и запуск отдельной попытки

Runner доставляет пакет, вызывает `fpga-dispatch submit`, опрашивает `status` и сохраняет готовый `result.json`. На стенде с одной платой worker выбирает следующую отправку автоматически. Для диагностики отдельного запуска остаётся команда runner.

## Размещение

Локальная доставка и runner входят в `dev`. Для локального адаптера бэкенд, каталог заданий и диспетчер доступны на одном Linux-хосте. Размещение для эксплуатации и схема сети до стенда остаются открытыми.

## Автоматическая очередь на одну плату

На Linux-хосте стенда укажите ту же базу, которую использует API. Выполните команды из `src/backend` в окружении бэкенда. Замените пути на пути стенда.

```bash
export DATABASE_URL=sqlite:////absolute/path/fpga.sqlite3
alembic upgrade head
python -m app.integrations.fpga.worker \
  --bindings /absolute/path/lab-bindings.json \
  --jobs-root /absolute/path/jobs \
  --dispatcher /absolute/path/repository/src/fpga/bin/fpga-dispatch \
  --run-config /absolute/path/integration.json
```

Оставьте процесс работающим. Студент отправляет код обычным способом. Worker выбирает старейшую ожидающую аппаратную попытку для лабораторной из bindings и сохраняет её ID в базе как занятую попытку до передачи диспетчеру. Попытки других лабораторных ждут настройки. После изменения bindings перезапустите процесс.

Пока первая проверка идёт, вторая ждёт. После обрыва связи обработчик повторяет работу с тем же ID. При повторной регистрации диспетчер узнаёт ранее принятый ID. После перезапуска worker продолжает начатую попытку. Если её состояние неизвестно, проверьте сообщение с run_id в журнале worker и журнал диспетчера. Следующая попытка начнётся после сохранения результата предыдущей. Все экземпляры worker одного стенда используют общие jobs-root и БД. При переходе с ручного режима сначала завершите или синхронизируйте предыдущий ручной запуск. Для ручной диагностики приостановите очередь.

**Проверка на C5G.** Отправьте два решения для настроенной лабораторной подряд. Запишите оба run_id. Во время первой проверки убедитесь через API, что вторая ещё queued. Перезапустите worker с теми же параметрами. Дождитесь двух результатов, проверьте порядок по started_at и finished_at. Для заведомо правильного решения ожидаются passed и hardware_verified=true. Отдельно запускать runner для каждой попытки не требуется.

## Запуск оператором

Сначала применить существующие миграции и создать отправку через сайт или Swagger.
В `GET /submissions/{submission_id}/run` взять `run_id`.
Подготовить bindings по [инструкции](fpga-package.md): реальный UUID лабораторной,
совпадающий kind и согласованный test_set. Пример И из seed не является счётчиком.
Для аппаратного запуска оператор подготавливает Quartus, плату, UART, конфигурацию
и пользовательский systemd версии 254 или новее.

Размещайте каталог заданий на дисковой файловой системе с достаточным
свободным местом. Если `/tmp` смонтирован как tmpfs, доступное там место
оценивается отдельно от места на диске. Исполнитель проверяет
[резерв для сборки](../../fpga/docs/pilot-limits.md) на файловой системе заданий.

Из `src/backend`, после подстановки действительных абсолютных путей:

```bash
DATABASE_URL=sqlite:////absolute/path/fpga.sqlite3 \
python -m app.integrations.fpga.runner \
  --run-id UUID_ПОПЫТКИ \
  --bindings /absolute/path/lab-bindings.json \
  --jobs-root /absolute/path/jobs \
  --dispatcher /absolute/path/repository/src/fpga/bin/fpga-dispatch \
  --run-config /absolute/path/integration.json \
  --public-vector-index 0
```

Индекс 0 открывать только если этот вектор разрешён для данной лабораторной.
Без аргумента видимость берётся из сохранённой попытки (по умолчанию всё скрыто).
CLI не принимает режим от студента и не меняет hardware на mock.

По умолчанию опрос раз в 3 секунды, ожидание 900 секунд и лимит отдельной команды
30 секунд. Настройки: `--poll-interval`, `--max-wait`, `--command-timeout`.
`--once` выполняет один шаг доставки/запуска/опроса. `--launch manual` оставляет
запуск fpga-run оператору, как предусмотрено диспетчером; это режим диагностики.
Код выхода 0 — шаг выполнен либо попытка завершена, не обязательно успешно.
Код 1 — ошибка одиночного шага; код 2 — исчерпан срок ожидания.

## Повторы и ошибки

- Повторять команду с тем же run_id. После потерянного ответа submit повтор
  возвращает existing; новая попытка и новый исходник не создаются.
- Незавершённую регистрацию в `.pending` восстанавливает повтор submit диспетчера.
- Если статус уже сохранён, runner продолжает опрос без повторной доставки.
- Завершённая запись в БД неизменяема: повтор команды не запускает плату заново.
- Сначала читается status, затем только при finished — result. Проверяются UUID,
  режим, формат и согласованность снимков; запись выполняется одной транзакцией.
- Отсутствующий/неполный результат, ошибочный JSON и конфликт версий оставляют
  прежнее состояние; следующий опрос повторяет чтение. При постоянной ошибке
  нужно проверить конфигурацию и журнал диспетчера.
- Команды передаются списком аргументов без shell. Общий вывод stdout/stderr
  ограничен 4 МиБ, время ожидания ограничено; при превышении убивается группа
  процессов вызова диспетчера. Независимый сервис systemd этим не отменяется.
- max-wait ограничивает цикл опроса; уже начатая команда может добавить до своего
  command-timeout, а доставка — до 5 секунд ожидания блокировки.
- Ошибки клиента не превращаются в выдуманный finished или hardware_verified.
  Сырые stderr, пути и исходники в API не передаются.
- Готовый результат и каталоги стенда не удаляются: вызов реализованного cleanup из runner ещё не подключён.

## Проверка без платы

```bash
python -m pytest -q tests/test_fpga_client_runner.py
```

Тест использует SQLite, регистрацию и отправку через HTTP, настоящий
fpga-dispatch с manual и fpga-run в mock, затем импорт результата и GET API.
Mock здесь — доверенная тестовая настройка, он не исполняет Verilog студента
и не доказывает работу платы. Проверяются hardware_verified=false, открытые тесты
и 404 для другого пользователя. Остальные тесты покрывают потерянный ответ,
повторы, таймаут, неверный UUID, ссылки и неполный результат.

## Что остаётся для кнопки на сайте

1. Настроить пути, лабораторную, test_set и открытые индексы.
2. Добавить обработчик сохраняемой очереди: брать ожидающие попытки автоматически,
   запускать на единственном стенде последовательно и возобновлять после перезапуска.
3. Подключить cleanup после сохранения результата.
4. Следующим этапом ограничить запуск действующей бронью. Лимит частоты попыток
   не добавлять: согласовано неограниченное количество отправок в пределах брони.

## Самостоятельная приёмка

Этот прогон проверяет одну отправку: выбор
run_id и запуск команды пока ручные, дальнейший опрос и импорт автоматические.
Использовать Linux, Python 3.11+, jq, make, gcc, Icarus и подготовленное окружение
Quartus/systemd/UART. Аппаратные настройки остаются у интегратора.

### 1. Подготовить окружение

Используйте актуальную рабочую копию `dev`: локальная доставка уже включена,
дополнительные ветка и merge не нужны. Из корня репозитория:

```bash
make -C src/fpga all
cd src/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
export DATABASE_URL="sqlite:///$(pwd)/fpga-integration.sqlite3"
python -m app.modules.labs.seed
```

### 2. Добавить отдельную техническую лабораторную Counter

Штатную seed-лабораторную И не использовать для counter-v1.
Следующий код создаёт отдельный тестовый Counter и его привязку, не меняя seed:

```bash
python - <<'PY'
import json
from pathlib import Path
from uuid import UUID
from sqlalchemy.orm import Session
from app.core.config import get_settings
from app.db.session import create_database_engine
from app.modules.labs.models import Lab

lab_id = UUID('b5f43be0-3f30-44b4-b891-721389962129')
source = Path('../fpga/examples/counter/student_top.v').read_text()
engine = create_database_engine(get_settings())
with Session(engine) as db, db.begin():
    lab = db.get(Lab, lab_id)
    if lab is None:
        db.add(Lab(id=lab_id, title='Техническая проверка: Counter',
                   description='Приёмка интеграции, не лабораторная курса.',
                   statement='Отправьте штатный пример counter/student_top.v.',
                   template=source, interface_description='student_top(clk, reset, din, dout)',
                   kind='sequential', is_published=True, is_demo=True))
    elif lab.kind != 'sequential' or not lab.is_demo:
        raise ValueError('This UUID already belongs to another laboratory')
engine.dispose()
state = Path.home() / '.local/share/fpga-platform'
state.mkdir(parents=True, exist_ok=True)
bindings = state / 'counter-bindings.json'
bindings.write_text(json.dumps({'schema_version': 1, 'labs': {
    str(lab_id): {'kind': 'sequential', 'test_set': 'counter-v1'}
}}, indent=2))
print('LAB_ID:', lab_id)
print('BINDINGS:', bindings)
PY
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Терминал с сервером оставить работающим. В новом терминале из корня этой
рабочей копии выполнить `cd src/frontend`, `npm ci`, `npm run dev`.
Открыть http://localhost:5173. Если аккаунта нет, создать его в
http://localhost:8000/docs через POST /auth/register, затем войти на сайте.
Пароль выбрать свой, минимум 12 символов. Открыть технический Counter и отправить
штатный исходник. Нормально, что до следующего шага статус остаётся queued.

### 3. Запустить эту отправку

В ответе GET /submissions/{submission_id}/run взять именно run_id, а не ID
лабораторной или отправки. Его можно посмотреть в Network браузера либо в Swagger
после POST /auth/login под тем же аккаунтом.

В третьем терминале перейти в src/backend той же рабочей копии:

```bash
source .venv/bin/activate
export DATABASE_URL="sqlite:///$(pwd)/fpga-integration.sqlite3"
build_root="$(cd ../fpga && pwd)/build"
mkdir -p -- "$build_root"
jobs_root=$(mktemp -d "$build_root/acceptance.XXXXXXXX")
mkdir -m 700 -- "$jobs_root/incoming"
python -m app.integrations.fpga.runner \
  --run-id UUID_ИЗ_ОТВЕТА_API \
  --bindings "$HOME/.local/share/fpga-platform/counter-bindings.json" \
  --dispatcher "$(cd ../fpga && pwd)/bin/fpga-dispatch" \
  --jobs-root "$jobs_root" \
  --run-config /АБСОЛЮТНЫЙ/ПУТЬ/К/integration.json \
  --public-vector-index 0 \
  --max-wait 1800
```

Подставьте UUID и абсолютный путь к конфигурации. Пример создаёт отдельный
каталог заданий внутри `build`. Для повторного опроса той же попытки
используйте сохранённый `jobs_root`.
integration.json должен содержать реальные Quartus, USB-Blaster, UART и лимиты.
Вызывать от пользователя с рабочим `systemctl --user`. Не ставить manual для
обычного прогона: иначе fpga-run автоматически не запустится.

### 4. Что считать успехом

- На сайте: queued → running → finished, открытый тест и полный отчёт.
- Для правильного Counter: result_status=passed и hardware_verified=true.
- В каталоге runs/<run_id>/output: согласованные status.json и result.json.
- Повтор команды с тем же run_id возвращает finished, повторной прошивки нет.
- Mock, один лишь finished или зелёный тест CI не доказывают работу платы.

Сценарий Counter подтверждён на C5G от отправки решения в браузере до полного
отчёта в истории. Runner запустили вручную для одной попытки. При `din=0x001`
после трёх тактов плата вернула ожидаемое `0x00003`. В отчёте показаны
«Проверено на плате», один пройденный открытый тест и два активных младших
светодиода. В JSON сохранены `status=passed` и `hardware_verified=true`.

При ошибке не менять run_id для той же попытки. Проверить журналы
`journalctl --user -u fpga-run-<run_id>.service` и output/logs.
Если попытка завершилась с `disk_space_low`, проверьте свободное место через
`df -h -- "$jobs_root"`. После выбора подходящего раздела отправьте решение
заново и используйте новый `run_id`.
Для разбора прислать run_id, state/stage/result_status из API и текст ошибки
сборки/запуска без паролей и токенов. Если runner достиг max-wait, сервис не отменён:
повторить ту же команду. В ручном режиме дождитесь finished перед запуском следующей попытки.

## Логи и доступность платы для фронтенда

Диспетчер хранит лог Quartus в `runs/<run_id>/output/logs/build.log`, лог загрузки на плату в `logs/program.log` того же каталога output. В `result.json` поле `logs` перечисляет созданные файлы. Если этап не начался, его лог может отсутствовать. После cleanup исходные журналы на стенде могут быть удалены.

Предложение для согласования с Вадимом и фронтендом:

| Данные | Предлагаемое поле | Правило |
| --- | --- | --- |
| Сообщения по собственной отправке | `GET /submissions/{id}/run`, `logs.build` и `logs.program` | Очищенный текст или null, пока журнала нет. До публикации согласовать объём, удаление локальных путей и хранение после cleanup. |
| Доступность платы | `state` и `checked_at` отдельного ответа о стенде | busy при активной аппаратной задаче, free после актуальной положительной проверки связи, unavailable при потере связи или устаревшей проверке. |

Сегодня `fpga-dispatch status --run-id` возвращает состояние конкретной попытки. Пустая очередь не подтверждает USB/JTAG-соединение. У Вадима нужно подтвердить источник сигнала доступности и срок его актуальности. Эти поля пока находятся на согласовании.
