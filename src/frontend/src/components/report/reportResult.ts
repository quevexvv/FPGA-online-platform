import { boardStateFromTest, mismatchedLeds } from '@/components/board/boardLayout';
import { stageLabels } from '@/components/workspace/runProgress';
import { RunStatus } from '@/types';

// Настроение итога: от него зависят значок и цвета карточки
export type ResultTone = 'success' | 'warning' | 'error' | 'info' | 'pending';

export interface ResultText {
  tone: ResultTone;
  title: string;
  description: string;
}

const NOT_YOUR_FAULT = 'Это не ошибка решения.';

// Что не совпало в первом непройденном открытом тесте: «Не совпал светодиод LEDR3 в тесте 3.»
function firstMismatch(run: RunStatus): string {
  const test = run.tests.find((item) => !item.match);
  if (!test) return '';
  const names = mismatchedLeds(boardStateFromTest(test));
  const number = test.vector_index + 1;
  if (names.length === 1) return `Не совпал светодиод ${names[0]} в тесте ${number}.`;
  return `Не совпали светодиоды ${names.join(', ')} в тесте ${number}.`;
}

// Заголовок и пояснение итога проверки
export function describeResult(run: RunStatus | null): ResultText {
  const inProgress = 'Отчёт обновится сам, когда проверка закончится.';
  if (!run) return { tone: 'pending', title: 'Загружаем результат проверки', description: '' };
  if (run.state === 'not_started') {
    return { tone: 'info', title: 'Проверка не запускалась', description: '' };
  }
  if (run.state === 'queued') {
    return { tone: 'pending', title: 'Решение в очереди', description: inProgress };
  }
  if (run.state === 'running') {
    const stage = run.stage ? stageLabels[run.stage] : 'Проверка';
    return { tone: 'pending', title: `${stage}...`, description: inProgress };
  }

  switch (run.result_status) {
    case 'passed':
      return {
        tone: 'success',
        title: 'Все проверки пройдены',
        description: 'Решение верно на всех входных значениях.',
      };
    case 'mismatch':
      // Открытые тесты прошли, значит, не прошли только скрытые
      if (run.tests.every((test) => test.match)) {
        return {
          tone: 'warning',
          title: 'Открытые примеры пройдены, но дополнительные проверки нет',
          description: 'Решение работает не для всех входных значений.',
        };
      }
      return {
        tone: 'warning',
        title: 'Результат не совпал с ожидаемым',
        description: `Сборка и прошивка прошли. ${firstMismatch(run)}`,
      };
    case 'build_error':
      return {
        tone: 'error',
        title: 'Ошибка сборки',
        description: 'Исправьте код по логу сборки. Тесты не запускались.',
      };
    case 'invalid_input':
      return {
        tone: 'error',
        title: 'Код не соответствует формату задания',
        description: 'Проверьте имя модуля и его порты. Сборка не запускалась.',
      };
    case 'board_error':
      return {
        tone: 'info',
        title: 'Проблема при прошивке или обмене со стендом',
        description: `${NOT_YOUR_FAULT} Показаны данные, полученные до сбоя.`,
      };
    case 'busy':
      return {
        tone: 'info',
        title: 'Стенд был занят',
        description: `${NOT_YOUR_FAULT} Попробуйте отправить его позже.`,
      };
    default:
      return {
        tone: 'info',
        title: 'Сбой платформы',
        description: `${NOT_YOUR_FAULT} Попробуйте отправить его позже.`,
      };
  }
}

export interface ResultStat {
  label: string;
  value: string;
}

// Числа справа в карточке итога: открытые примеры, дополнительные проверки, время
export function resultStats(run: RunStatus | null): ResultStat[] {
  if (!run || run.state !== 'finished') return [];
  const stats: ResultStat[] = [];
  const summary = run.summary;
  const publicPassed = run.tests.filter((test) => test.match).length;

  if (run.result_status === 'board_error' && summary) {
    // Проверка оборвалась: важнее, сколько тестов успели выполнить
    stats.push({ label: 'Выполнено тестов', value: `${summary.executed} из ${summary.planned}` });
  } else {
    if (run.tests.length > 0) {
      stats.push({ label: 'Открытые примеры', value: `${publicPassed} из ${run.tests.length}` });
    }
    // Скрытые тесты: всё, что выполнено, минус открытые
    const hiddenTotal = summary ? summary.executed - run.tests.length : 0;
    if (summary && hiddenTotal > 0) {
      const hiddenPassed = summary.passed - publicPassed;
      stats.push({ label: 'Дополнительные проверки', value: `${hiddenPassed} из ${hiddenTotal}` });
    }
  }

  if (run.elapsed_seconds > 0) {
    stats.push({ label: 'Время проверки', value: `${Math.round(run.elapsed_seconds)} сек` });
  }
  return stats;
}

// Короткий итог для таблицы истории: «Несовпадение тестов (LEDR3 не сошёлся)»
export function shortResult(run: RunStatus): ResultText {
  const tone = describeResult(run).tone;
  const text = (title: string) => ({ tone, title, description: '' });

  if (run.state === 'not_started') return text('Не запускалась');
  if (run.state === 'queued') return text('В очереди');
  if (run.state === 'running') return text(run.stage ? stageLabels[run.stage] : 'Проверка');

  switch (run.result_status) {
    case 'passed':
      return text('Успешно (все тесты пройдены)');
    case 'mismatch': {
      const failed = run.tests.find((test) => !test.match);
      if (!failed) return text('Не пройдены дополнительные проверки');
      const names = mismatchedLeds(boardStateFromTest(failed));
      const verb = names.length === 1 ? 'не сошёлся' : 'не сошлись';
      return text(`Несовпадение тестов (${names.join(', ')} ${verb})`);
    }
    case 'build_error':
      return text('Ошибка сборки');
    case 'invalid_input':
      return text('Неверный формат кода');
    case 'board_error':
      return text('Сбой оборудования');
    case 'busy':
      return text('Стенд был занят');
    default:
      return text('Сбой платформы');
  }
}
