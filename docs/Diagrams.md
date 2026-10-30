# Диаграммы последовательности (Sequence Diagrams)
Этот документ описывает ключевые сценарии взаимодействия между Фронтендом, Бэкендом, Диспетчером (fpga-dispatch) и платой C5G.

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
    participant Quartus as Quartus CLI
    participant FPGA as Плата C5G

    Student->>FE: Нажимает "Отправить на проверку"
    FE->>BE: POST /api/v1/submit {code}
    BE->>Disp: submit --run-id <uuid> --mode hardware
    Disp-->>BE: {"disposition": "accepted"}
    BE-->>FE: 202 Accepted
    FE-->>Student: Показывает стадию "Сборка..."
    
    par Асинхронная работа на стенде
        Disp->>Quartus: quartus_sh --flow compile
        Quartus-->>Disp: Успех (.sof создан)
        Disp->>FPGA: quartus_pgm (прошивка)
        Disp->>FPGA: Тесты через UART
        FPGA-->>Disp: Ответы совпали
    end
    
    BE->>Disp: status --run-id <uuid>
    Disp-->>BE: state=finished, status=passed
    BE-->>FE: WebSocket: {status: "passed", hardware_verified: true}
    FE-->>Student: Показывает "Все проверки пройдены" и модель платы
```

---
## 2. Ошибка сборки
*Описание: Студент отправляет верный код, система собирает его, прошивает плату и возвращает успешный результат.*

```mermaid
sequenceDiagram
    autonumber
    actor Student as Студент
    participant FE as Фронтенд
    participant BE as Бэкенд
    participant Disp as fpga-dispatch
    participant Quartus as Quartus CLI

    Student->>FE: Отправляет код с ошибкой
    FE->>BE: POST /api/v1/submit {code}
    BE->>Disp: submit --run-id <uuid>
    Disp-->>BE: {"disposition": "accepted"}
    BE-->>FE: 202 Accepted
    FE-->>Student: Показывает стадию "Сборка..."
    
    Disp->>Quartus: quartus_sh --flow compile
    Note over Quartus: Ошибка синтаксиса в строке 14
    Quartus-->>Disp: Exit code != 0
    
    Disp->>Disp: Парсит лог, извлекает суть ошибки
    Disp-->>BE: status=finished, result=build_error
    BE-->>FE: {status: "build_error", logs: "..."}
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

    StudentA->>BE: Отправляет код
    BE->>Disp: submit --run-id <uuid_A>
    Disp-->>BE: accepted
    
    StudentB->>BE: Отправляет код
    BE->>Disp: submit --run-id <uuid_B>
    Disp-->>BE: {"disposition": "busy"}
    BE-->>StudentB: {status: "busy", retry_after: 300}
    StudentB-->>StudentB: Видит таймер "Стенд занят"
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

    Student->>FE: Нажимает "Посмотреть пример"
    FE->>BE: GET /api/v1/labs/{lab_id}/example
    
    Note over BE: Запрос к БД примеров<br/>БЕЗ вызова fpga-dispatch!
    
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
    participant SSH as SSH-туннель
    participant Systemd as systemd (на хосте)
    participant Disp as fpga-run

    BE->>SSH: submit --run-id <uuid>
    SSH->>Systemd: Запуск service (linger, Restart=no)
    Systemd->>Disp: Запуск сборки
    Systemd-->>SSH: accepted
    SSH-->>BE: accepted
    
    Note over BE,SSH: Обрыв SSH-сессии!
    
    BE->>SSH: Переподключение через 5 минут
    BE->>SSH: status --run-id <uuid>
    SSH->>Systemd: Запрос статуса
    Systemd-->>SSH: state=finished, status=passed
    SSH-->>BE: Результат успешно получен
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
    FE->>BE: POST /api/v1/submit {code}
    BE->>Disp: submit --run-id <uuid> --mode hardware
    Disp->>FS: Записывает status.json (state=starting)
    Disp-->>BE: {"disposition": "accepted"}
    BE-->>FE: 202 Accepted
    FE-->>Student: Показывает стадию "Сборка..."
    
    Note over Run, FPGA: Асинхронная работа на стенде
    Disp->>Run: Запуск через systemd (linger)
    Run->>FS: Обновляет stage=building
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
        Disp-->>BE: state=finished, result=board_error
    end
    
    BE->>FS: Читает result.json и логи
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

# Use Case Diagram: Платформа удалённых лабораторных


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
    UC6 -.->|<<include>>| UC11
    UC6 -.->|<<include>>| UC13
    UC12 -.->|<<include>>| UC17
    UC10 -.->|<<include>>| UC11
    UC10 -.->|<<include>>| UC13
    UC13 -.->|<<include>>| UC14
    UC14 -.->|<<include>>| UC15
    UC15 -.->|<<include>>| UC16
    UC16 --> FPGA

    %% === ПРИМЕНЕНИЕ СТИЛЕЙ ===
    class Teacher,Student,Backend actor
    class FPGA external
    class UC1,UC2,UC5,UC6,UC7,UC8,UC9,UC10,UC11,UC12 uc
    class UC16,UC17,UC18,UC19,UC20 internal
```