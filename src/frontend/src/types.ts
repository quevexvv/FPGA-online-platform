export type LabStatus = 'completed' | 'in_progress' | 'not_started';
export type DeadlineType = 'completed' | 'today' | 'future';

    //Данные из API (GET /labs). Имена полей совпадают с ответом сервера
export type LabKind = 'combinational' | 'sequential';

    // Краткая карточка из списка
export interface LabSummary {
  id: string; // UUID, например '346674de-1837-4d21-a234-2e61a85a5701'
  title: string;
  description: string;
  kind: LabKind;
  is_demo: boolean;
}

    // Полная карточка (GET /labs/{id})
export interface LabDetail extends LabSummary {
  statement: string;
  template: string;
  interface_description: string;
}

    // Временные поля (в апи пока нет)

export interface LabProgress {
  subtitle: string;
  deadline: string;
  deadlineType: DeadlineType;
  status: LabStatus;
  isLocked: boolean;
}

// Строка таблицы лабораторных: данные из API плюс временные поля
export type LabItem = LabSummary & LabProgress;

// Пользователь GET /auth/me

export type UserRole = 'student' | 'teacher';

export interface User { // Поля в точности как в ответе сервера /auth/me
  id: string;
  email: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  created_at: string; // дата и время в формате ISO (2026-11-11T22:03:20Z)
}

// Отправленное решение (ответ POST /labs/{id}/submissions)
export interface SubmissionSummary {
  id: string;
  lab_id: string;
  created_at: string; // дата и время в UTC, например '2026-11-12T16:03:38Z'
}

// Статус проверки решения (GET /submissions/{id}/run). 
// Имена полей как в ответе сервера
export type RunState = 'not_started' | 'queued' | 'running' | 'finished';
export type RunStage =
  | 'dispatch'
  | 'validating'
  | 'locking'
  | 'building'
  | 'programming'
  | 'testing'
  | 'finalizing';
export type RunResult =
  | 'passed'
  | 'mismatch'
  | 'build_error'
  | 'board_error'
  | 'invalid_input'
  | 'busy'
  | 'internal_error';

// Итоги по всем тестам, включая скрытые
export interface RunSummary {
  planned: number;
  executed: number;
  passed: number;
  failed: number;
}

// Один открытый тест: что подали на вход, что получили и что ожидали
export interface RunTest {
  vector_index: number;
  din: string; // вход, hex-строка из 10 бит, например '0x003'
  steps: number; // сколько тактов прошло
  dout: string; // полученный выход, hex-строка из 18 бит, например '0x00001'
  expected_dout: string; // ожидаемый выход
  mask: string; // какие биты выхода сравниваются
  match: boolean;
}

export interface RunStatus {
  submission_id: string;
  run_id: string | null; // null — проверку ещё не запускали
  state: RunState;
  stage: RunStage | null;
  mode: 'hardware' | 'mock' | null;
  result_status: RunResult | null; // null, пока проверка не закончилась
  hardware_verified: boolean;
  queued_at: string | null;
  started_at: string | null;
  updated_at: string | null;
  finished_at: string | null;
  elapsed_seconds: number;
  poll_after_seconds: number | null; // через сколько секунд спросить снова; null — больше не нужно
  summary: RunSummary | null;
  tests: RunTest[];
  error: { code: RunResult; message: string } | null;
}