import { RunResult, RunStage, RunStatus } from '@/types';

// Подробные названия этапов проверки на стенде
export const stageLabels: Record<RunStage, string> = {
  dispatch: 'Передача на стенд',
  validating: 'Проверка файлов',
  locking: 'Ожидание свободной платы',
  building: 'Сборка',
  programming: 'Прошивка платы',
  testing: 'Тестирование',
  finalizing: 'Подведение итогов',
};

// Итоги проверки
export const resultLabels: Record<RunResult, string> = {
  passed: 'Все тесты пройдены',
  mismatch: 'Есть несовпадения с ожидаемым результатом',
  build_error: 'Ошибка сборки',
  board_error: 'Не удалось завершить проверку на плате',
  invalid_input: 'Решение не принято: нарушен формат задания',
  busy: 'Стенд был занят, проверка не выполнена',
  internal_error: 'Внутренняя ошибка проверки',
};

// Шаги, которые видит студент. Этапов у стенда семь, шагов на экране шесть:
// передача на стенд входит в «Очередь», ожидание платы — в «Проверку файлов»
export const steps = [
  'Очередь',
  'Проверка файлов',
  'Сборка',
  'Прошивка',
  'Тестирование',
  'Завершение',
];

const stageStep: Record<RunStage, number> = {
  dispatch: 0,
  validating: 1,
  locking: 1,
  building: 2,
  programming: 3,
  testing: 4,
  finalizing: 5,
};

// На каком шаге остановилась неудачная проверка
const failedStep: Record<Exclude<RunResult, 'passed'>, number> = {
  busy: 0,
  invalid_input: 1,
  build_error: 2,
  board_error: 3,
  mismatch: 4,
  internal_error: 5,
};

export type StepState = 'done' | 'current' | 'failed' | 'pending';

// Состояние каждого шага для текущего статуса проверки
export function getStepStates(run: RunStatus | null): StepState[] {
  if (!run || run.state === 'not_started') return steps.map(() => 'pending');

  let current = 0;
  let isFailed = false;
  if (run.state === 'running' && run.stage) {
    current = stageStep[run.stage];
  } else if (run.state === 'finished') {
    if (run.result_status === 'passed' || run.result_status === null) {
      // Всё пройдено: «текущего» шага нет
      current = steps.length;
    } else {
      current = failedStep[run.result_status];
      isFailed = true;
    }
  }

  return steps.map((_, index) => {
    if (index < current) return 'done';
    if (index === current) return isFailed ? 'failed' : 'current';
    return 'pending';
  });
}
