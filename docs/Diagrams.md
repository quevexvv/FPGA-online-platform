# Диаграммы последовательности (Sequence Diagrams)
Этот документ описывает ключевые сценарии взаимодействия между Фронтендом, Бэкендом, Диспетчером (fpga-dispatch) и платой C5G.

Диаграммы показывают целевое поведение по [контракту](contract.md),
а не готовность реализации. API сайта и способ доставки прогресса выбираются
отдельно. Перед submit бэкенд завершает загрузку manifest и исходников;
при разных хостах файлы передаются через SFTP, команды — через SSH.
В браузер попадают только разрешённые данные, без скрытых векторов и эталонов.
Обозначения uuid_A, uuid_B, uuid_C и uuid_demo представляют разные UUID.

---

## 1. Успешная отправка и проверка кода
*Описание: Студент отправляет верный код, система собирает его, прошивает плату и возвращает успешный результат.*

```mermaid
sequenceDiagram
    autonumber
    actor Student as Студент
    participant FE as Фронтенд
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant Run as fpga-run (systemd)
    participant FS as Файлы запуска
    participant Quartus as Quartus CLI
    participant FPGA as Плата C5G

    Student->>FE: Нажимает "Отправить на проверку"
    FE->>BE: Отправляет решение через API
    BE->>FS: Завершает загрузку manifest и исходников
    BE->>Disp: submit --run-id <uuid> --mode hardware
    Disp->>FS: Публикует input, регистрацию и starting/dispatch
    Disp-->>BE: {"disposition": "accepted"}
    BE-->>FE: Задание зарегистрировано
    FE-->>Student: Показывает текущую стадию

    Disp->>Run: Независимый запуск, linger, Restart=no
    Run->>Run: Валидация и блокировка стенда
    Run->>Quartus: quartus_sh --flow compile
    Quartus-->>Run: Успех (.sof создан)
    Run->>FPGA: quartus_pgm (прошивка)
    Run->>FPGA: Тесты через UART
    FPGA-->>Run: Наблюдения
    Run->>Run: Сравнение с доверенным эталоном
    Run->>FS: Атомарно result.json, status=passed
    Run->>FS: Затем status.json, state=finished, result_status=passed

    BE->>Disp: status --run-id <uuid>
    Disp-->>BE: state=finished, result_status=passed
    BE->>FS: Читает result.json и логи, сохраняет историю
    BE->>BE: Фильтрует скрытые проверки и логи
    BE-->>FE: Итог passed, hardware_verified=true, разрешённый отчёт
    FE-->>Student: Показывает "Все проверки пройдены" и модель платы
```

---
## 2. Ошибка сборки
*Описание: Код не собирается. Исполнитель сохраняет лог и возвращает build_error без прошивки платы.*

```mermaid
sequenceDiagram
    autonumber
    actor Student as Студент
    participant FE as Фронтенд
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant Run as fpga-run (systemd)
    participant FS as Файлы запуска
    participant Quartus as Quartus CLI

    Student->>FE: Отправляет код с ошибкой
    FE->>BE: Отправляет решение через API
    BE->>Disp: submit --run-id <uuid> --mode hardware
    Disp->>FS: Публикует input, регистрацию и starting/dispatch
    Disp-->>BE: {"disposition": "accepted"}
    BE-->>FE: Задание зарегистрировано
    Disp->>Run: Независимый запуск через systemd
    Run->>Run: Валидация и блокировка стенда

    Run->>Quartus: quartus_sh --flow compile
    Note over Quartus: Ошибка синтаксиса в строке 14
    Quartus-->>Run: Exit code != 0

    Run->>FS: Сохраняет лог и result.json, status=build_error
    Run->>FS: Затем status.json, state=finished, result_status=build_error
    BE->>Disp: status --run-id <uuid>
    Disp-->>BE: state=finished, result_status=build_error
    BE->>FS: Забирает результат и логи
    BE-->>FE: Build_error и разрешённые логи
    FE-->>Student: Показывает "Ошибка сборки" и консоль с логом
```

---
## 3. Стенд занят
*Описание: Плата уже выполняет задачу другого студента. Система не ставит в очередь на уровне железа, а возвращает статус busy.*

```mermaid
sequenceDiagram
    autonumber
    actor StudentA as Студент А
    actor StudentB as Студент Б
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant Run as fpga-run (systemd)
    participant FS as Файлы запуска

    StudentA->>BE: Отправляет код
    BE->>Disp: submit --run-id uuid_A --mode hardware
    Disp->>FS: Публикует starting/dispatch для uuid_A
    Disp-->>BE: accepted
    Disp->>Run: Запуск uuid_A, блокировка получена

    StudentB->>BE: Отправляет код
    BE->>Disp: submit --run-id uuid_B --mode hardware
    Disp->>FS: Публикует starting/dispatch для uuid_B
    Disp-->>BE: accepted
    Disp->>Run: Запуск uuid_B
    Run->>Run: Блокировка занята, без ожидания
    Run->>FS: result.json, status=busy, hardware_verified=false
    Run->>FS: Затем status.json, state=finished, result_status=busy
    BE->>Disp: status --run-id uuid_B
    Disp-->>BE: state=finished, result_status=busy
    BE->>FS: Читает result.json для uuid_B
    BE-->>StudentB: Стенд занят, отправка остаётся в очереди
    Note over BE: Позже новое выполнение получает uuid_C, не uuid_B
    BE->>Disp: submit --run-id uuid_C --mode hardware
```

---
## 4. Mock: Просмотр примера
*Описание: Студент смотрит, как работает правильное решение. Физическая плата не задействуется.*

```mermaid
sequenceDiagram
    autonumber
    actor Student as Студент
    participant FE as Фронтенд
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant Run as fpga-run (systemd)
    participant FS as Файлы запуска

    Student->>FE: Нажимает "Посмотреть пример"
    FE->>BE: Запрашивает готовый пример через API

    BE->>Disp: submit --run-id uuid_demo --mode mock
    Disp->>FS: Публикует starting/dispatch
    Disp-->>BE: accepted
    Disp->>Run: Независимый запуск mock
    Note over Run: Без сборки HDL, прошивки и UART
    Run->>FS: Готовые данные, result.json с mode=mock, hardware_verified=false
    Run->>FS: Затем status.json, state=finished
    BE->>Disp: status --run-id uuid_demo
    Disp-->>BE: state=finished, result_status=passed, mode=mock
    BE->>FS: Читает демонстрационный результат

    BE-->>FE: {mode: "mock", hardware_verified: false, data: {...}}
    FE-->>Student: Рисует модель платы (светодиоды горят)
    Note over Student: Код решения скрыт<br/>Аппаратная проверка не требуется
```

---

## 5. Обрыв связи и восстановление
*Описание: SSH-сессия обрывается во время сборки. Благодаря systemd задача продолжается в фоне.*

```mermaid
sequenceDiagram
    autonumber
    participant BE as Бэкенд (клиент)
    participant SSH as SSH-соединение
    participant Disp as fpga-dispatch
    participant Systemd as systemd (на хосте)
    participant Run as fpga-run
    participant FS as Файлы запуска

    BE->>SSH: fpga-dispatch submit --run-id uuid --mode hardware
    SSH->>Disp: submit
    Disp->>FS: Публикует регистрацию и starting/dispatch
    Disp-->>SSH: accepted
    SSH-->>BE: accepted
    Disp->>Systemd: Запуск service (linger, Restart=no)
    Systemd->>Run: Запуск исполнителя

    Note over BE,SSH: Обрыв SSH-сессии!

    Run->>FS: Продолжает работу и публикует result.json
    Run->>FS: Затем state=finished
    BE->>SSH: Переподключение, fpga-dispatch status --run-id uuid
    SSH->>Disp: status того же ID
    Disp->>FS: Проверяет процесс и читает статус
    Disp-->>SSH: state=finished, result_status=passed
    SSH-->>BE: Состояние получено, результат забирается через SFTP
    Note over BE,Disp: Если ответ submit потерян, проверяется тот же ID, без повторного исполнения
```

---

## 6. Сбой прошивки или обмена со стендом (Board Error)
*Описание: Сборка прошла успешно, но на этапе прошивки или тестирования по UART произошёл сбой. Система корректно завершает процесс, сохраняет частичные данные и возвращает понятную ошибку.*

```mermaid
sequenceDiagram
    autonumber
    actor Student as Студент
    participant FE as Фронтенд
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant Run as fpga-run<br/>(systemd service)
    participant FS as Файловая система<br/>(status/result.json)
    participant Quartus as Quartus CLI
    participant FPGA as Плата C5G (UART)

    Student->>FE: Отправляет код на проверку
    FE->>BE: Отправляет решение через API
    BE->>Disp: submit --run-id <uuid> --mode hardware
    Disp->>FS: Записывает status.json (state=starting)
    Disp-->>BE: {"disposition": "accepted"}
    BE-->>FE: Задание зарегистрировано
    FE-->>Student: Показывает текущую стадию

    Note over Run, FPGA: Асинхронная работа на стенде
    Disp->>Run: Запуск через systemd (linger)
    Run->>FS: Обновляет state=running, stage=building
    Run->>Quartus: quartus_sh --flow compile
    Quartus-->>Run: Успех (.sof создан)

    Run->>FS: Обновляет stage=programming
    Run->>FPGA: quartus_pgm (прошивка)
    FPGA-->>Run: Ошибка прошивки (или Успех)

    alt Прошивка успешна, сбой на этапе тестирования
        Run->>FS: Обновляет stage=testing
        Run->>FPGA: Отправка тестовых векторов через UART
        Note over FPGA: Обрыв USB-кабеля или<br/>таймаут ответа UART
        FPGA-->>Run: Нет ответа / Ошибка порта
    end

    Note over Run, FS: Обработка сбоя (Board Error)
    Run->>Run: Принудительно убивает дерево<br/>аппаратных процессов
    Run->>Run: Сохраняет доступные логи<br/>и частичные наблюдения (если были)
    Run->>FS: Атомарно записывает result.json:<br/>status=board_error<br/>hardware_verified=false<br/>observations=[частичные данные]
    Run->>FS: Обновляет status.json (state=finished)
    Note over Run: Блокировка стенда освобождается<br/>только после убийства процессов

    loop Опрос статуса
        BE->>Disp: status --run-id <uuid>
        Disp->>FS: Читает status.json
        Disp-->>BE: state=finished, result_status=board_error
    end

    BE->>FS: Читает result.json и логи
    BE->>BE: Фильтрует скрытые наблюдения и логи
    BE-->>FE: {status: "board_error", hardware_verified: false}
    FE-->>Student: Показывает: "Проблема при прошивке<br/>или обмене со стендом, а не ошибка решения"
```

---

## 7.Очистка завершённого задания (Cleanup)
*Описание: Бэкенд сохранил результат и логи у себя и запрашивает очистку временных файлов на стенде, чтобы освободить место для новых задач. Система гарантирует, что активные задачи не будут удалены, а повторный вызов безопасен.*

```mermaid
sequenceDiagram
    autonumber
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant FS as Файловая система<br/>(runs/<run_id>/)

    Note over BE: Бэкенд успешно сохранил<br/>result.json и логи у себя

    BE->>Disp: cleanup --run-id <uuid>

    alt Запуск ещё активен (state != finished)
        Disp->>FS: Читает status.json
        Note over Disp: Защита от случайного<br/>удаления работающей задачи
        Disp-->>BE: Ошибка: "Нельзя очистить активный запуск"
        Note over BE: Задача остаётся в очереди<br/>или ожидает завершения

    else Запуск уже очищен (есть отметка cleaned)
        Disp->>FS: Проверяет наличие отметки cleaned
        Note over Disp: Идемпотентность:<br/>повторный вызов безопасен
        Disp-->>BE: Успех (ничего не удаляется)

    else Запуск завершён (state = finished)
        Disp->>FS: Проверяет status.json (state=finished)
        Disp->>FS: Удаляет каталоги work/, input/, output/
        Note over FS: Файлы Quartus, логи и<br/>промежуточные данные удалены

        Disp->>FS: Создаёт/обновляет минимальную<br/>отметку run_id + cleaned
        Note over FS: Отметка сохраняется до конца пилота,<br/>чтобы предотвратить повторный submit

        Disp-->>BE: Успех: "Очищено"
    end
```

---

# Диаграмма вариантов использования

```mermaid
flowchart LR
    %% === СТИЛИ ===
    classDef actor fill:#ff66b2,stroke:#cc0066,color:white,stroke-width:2px
    classDef uc fill:#9999ff,stroke:#333399,color:white,stroke-width:1px
    classDef internal fill:#fffacd,stroke:#b8860b,color:#333333,stroke-width:1px
    classDef external fill:#90ee90,stroke:#228b22,color:black,stroke-width:2px

    %% === АКТОРЫ (розовые) ===
    Teacher([Преподаватель])
    Student([Студент])
    Backend([Бэкенд-система])
    FPGA([Плата C5G])

    %% === USE CASES СТУДЕНТА (голубые) ===
    UC1("Авторизоваться")
    UC2("Посмотреть пример (mock)")
    UC3("Открыть редактор кода")
    UC4("Повторить отправку решения")
    UC5("Посмотреть список лабораторных")
    UC6("Отправить решение на проверку")


    %% === USE CASES ПРЕПОДАВАТЕЛЯ ===
    UC7("Посмотреть результаты студентов")

    %% === USE CASES БЭКЕНДА ===
    UC8("Опросить статус")
    UC9("Очистить задание")
    UC10("Вызвать fpga-dispatch submit")

    %% === ВНУТРЕННИЕ (жёлтые) ===
    UC11("Валидация манифеста")
    UC12("Посмотреть стадии проверки")
    UC13("Проверка занятости стенда")
    UC14("Сборка в Quartus")
    UC15("Прошивка платы")
    UC16("Аппаратное тестирование")
    UC17("Отчёт и модель")
    UCHW("Аппаратный путь (hardware)")

    %% === СВЯЗИ ===
    Teacher --> UC7
    Teacher --> UC1
    Student --> UC1
    Student --> UC2
    Student --> UC3
    Student --> UC4
    Student --> UC5
    Student --> UC6
    Backend --> UC8
    Backend --> UC9
    Backend --> UC10

    UC6 -.->|<<include>>| UC12
    UC6 -.->|<<include>>| UC10
    UC2 -.->|<<include>>| UC10
    UC6 -.->|<<include>>| UC17
    UC10 -.->|<<include>>| UC11
    UCHW -.->|hardware| UC10
    UCHW -.->|<<include>>| UC13
    UCHW -.->|<<include>>| UC14
    UC14 -.->|<<include>>| UC15
    UC15 -.->|<<include>>| UC16
    UC16 --> FPGA

    %% === ПРИМЕНЕНИЕ СТИЛЕЙ ===
    class Teacher,Student,Backend actor
    class FPGA external
    class UC1,UC2,UC5,UC6,UC7,UC8,UC9,UC10,UC11,UC12 uc
    class UC13,UC14,UC15,UC16,UC17,UCHW internal
```
