# Запуск и получение результата одной попытки

Продолжение ONL-92 за 18–19 ноября: после доставки пакета бэкенд вызывает
`fpga-dispatch submit`, опрашивает `status` и сохраняет готовый `result.json`.
Команду запускает оператор для уже существующего `run_id`. Запуск из HTTP,
автоматический выбор всех ожидающих отправок, бронирование и SSH ещё не подключены.

## Размещение

Подтверждено 19.11.2026: бэкенд работает на ноутбуке Вадима рядом с диспетчером,
одна плата подключена к этому ноутбуку по проводу. БД и каталог заданий доступны
локально. Для этого адаптера требуется Linux-хост диспетчера.
Каталоги и исполняемый файл принадлежат доверенной учётной записи оператора.
Это локальный адаптер, не доставка с сервера на отдельный ноутбук через сеть.
До запуска на настоящей плате Вадим передаёт точные пути и конфигурацию стенда.
README, PostgreSQL и Docker для этой доработки не меняются.

## Запуск оператором

Сначала применить существующие миграции и создать отправку через сайт или Swagger.
В `GET /submissions/{submission_id}/run` взять `run_id`.
Подготовить bindings по [инструкции](fpga-package.md): реальный UUID лабораторной,
совпадающий kind и согласованный test_set. Пример И из seed не является счётчиком.
Для аппаратного запуска Вадим подготавливает Quartus, плату, UART, конфигурацию
и пользовательский systemd версии 254 или новее по своей инструкции.

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
- Готовый результат и каталоги стенда не удаляются: cleanup зависит от PR #35.

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

1. Получить от Вадима пути к fpga-dispatch, jobs и integration.json на его ноутбуке,
   согласовать лабораторную, test_set и открытые индексы. Сетевой транспорт не требуется.
2. Добавить обработчик сохраняемой очереди: брать ожидающие попытки автоматически,
   запускать на единственном стенде последовательно и возобновлять после перезапуска.
   CLI одной попытки ещё не решает параллельные отправки разных пользователей.
3. Выполнить hardware-прогон вместе с Вадимом; Арсению проверить результат на сайте.
4. Подключить cleanup после сохранения результата и принятия PR #35.
5. Следующим этапом ограничить запуск действующей бронью. Лимит частоты попыток
   не добавлять: согласовано неограниченное количество отправок в пределах брони.

## Самостоятельная приёмка для Вадима

Ивану присутствовать не требуется. Этот прогон проверяет одну отправку: выбор
run_id и запуск команды пока ручные, дальнейший опрос и импорт автоматические.
Использовать Linux, Python 3.11+, jq, make, gcc, Icarus и подготовленное окружение
Quartus/systemd/UART. Аппаратные настройки остаются у интегратора.

### 1. Подготовить отдельную рабочую копию

Из существующего репозитория (имя новой папки/ветки должно быть свободно):

```bash
git fetch origin
git worktree add -b test/backend-fpga ../fpga-integration-check origin/dev
cd ../fpga-integration-check
git merge --no-edit origin/feature/fpga-local-delivery
make -C src/fpga all
cd src/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
export DATABASE_URL="sqlite:///$(pwd)/fpga-integration.sqlite3"
python -m app.modules.labs.seed
```

Это соединяет актуальный фронтенд из dev и бэкенд PR #36 в отдельной локальной
ветке, не изменяя текущую рабочую копию Вадима. Публиковать эту тестовую ветку не нужно.
Если merge сообщил конфликт, остановиться и прислать его текст.

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
python -m app.integrations.fpga.runner \
  --run-id UUID_ИЗ_ОТВЕТА_API \
  --bindings "$HOME/.local/share/fpga-platform/counter-bindings.json" \
  --dispatcher "$(cd ../fpga && pwd)/bin/fpga-dispatch" \
  --jobs-root /АБСОЛЮТНЫЙ/ПУТЬ/К/КАТАЛОГУ/ЗАДАНИЙ \
  --run-config /АБСОЛЮТНЫЙ/ПУТЬ/К/integration.json \
  --public-vector-index 0 \
  --max-wait 1800
```

Заменить UUID и два пути. jobs-root и его incoming должны существовать и быть
доступны только оператору; использовать выделенный каталог для этой приёмки.
integration.json должен содержать реальные Quartus, USB-Blaster, UART и лимиты.
Вызывать от пользователя с рабочим `systemctl --user`. Не ставить manual для
обычного прогона: иначе fpga-run автоматически не запустится.

### 4. Что считать успехом

- На сайте: queued → running → finished, открытый тест и полный отчёт.
- Для правильного Counter: result_status=passed и hardware_verified=true.
- В каталоге runs/<run_id>/output: согласованные status.json и result.json.
- Повтор команды с тем же run_id возвращает finished, повторной прошивки нет.
- Mock, один лишь finished или зелёный тест CI не доказывают работу платы.

При ошибке не менять run_id для той же попытки. Проверить журналы
`journalctl --user -u fpga-run-<run_id>.service` и output/logs.
Для разбора прислать run_id, state/stage/result_status из API и текст ошибки
сборки/запуска без паролей и токенов. Если runner достиг max-wait, сервис не отменён:
повторить ту же команду. До автоматической очереди запускать только одну попытку
за раз и дождаться finished перед следующей.
