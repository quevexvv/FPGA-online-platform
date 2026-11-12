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