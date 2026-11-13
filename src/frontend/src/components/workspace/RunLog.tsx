import React from 'react';
import { makeStyles, tokens } from '@fluentui/react-components';
import { appTokens } from '@/theme/themes';
import { RunStatus } from '@/types';
import { getStepStates, resultLabels, stageLabels, steps } from './runProgress';

// info — всё идёт хорошо, status — ожидание или предупреждение, error — ошибка
type LineKind = 'info' | 'status' | 'error' | 'muted';

interface LogLine {
  kind: LineKind;
  text: string;
}

const prefixes: Record<LineKind, string> = {
  info: '[INFO]',
  status: '[STATUS]',
  error: '[STATUS]',
  muted: '',
};

// Строки терминала по текущему статусу проверки
function buildLines(
  run: RunStatus | null,
  submitMessage: string | null,
  submitError: string | null,
  isConnectionLost: boolean,
  runError: string | null,
): LogLine[] {
  const lines: LogLine[] = [];

  if (submitError) lines.push({ kind: 'error', text: submitError });
  if (!submitMessage && !run && !runError) {
    lines.push({ kind: 'muted', text: 'Напишите решение и нажмите «Отправить на проверку»' });
    return lines;
  }
  if (submitMessage) lines.push({ kind: 'info', text: submitMessage });
  if (runError) {
    lines.push({ kind: 'error', text: runError });
    return lines;
  }

  if (!run) {
    lines.push({ kind: 'status', text: 'Узнаём статус проверки...' });
  } else if (run.state === 'not_started') {
    lines.push({ kind: 'status', text: 'Проверка этого решения не запускалась' });
  } else if (run.state === 'queued') {
    lines.push({ kind: 'status', text: 'В очереди на проверку' });
  } else {
    // Пройденные шаги
    const states = getStepStates(run);
    steps.forEach((label, index) => {
      if (states[index] === 'done') lines.push({ kind: 'info', text: `${label}: успешно` });
    });

    if (run.state === 'running' && run.stage) {
      const seconds = Math.round(run.elapsed_seconds);
      lines.push({ kind: 'status', text: `${stageLabels[run.stage]}... (${seconds} с)` });
    }

    if (run.state === 'finished') {
      const isPassed = run.result_status === 'passed';
      const title = run.result_status ? resultLabels[run.result_status] : 'Проверка завершена';
      lines.push({ kind: isPassed ? 'info' : 'error', text: title });
      if (run.error) lines.push({ kind: 'error', text: run.error.message });

      const summary = run.summary;
      if (summary && summary.executed > 0) {
        // Скрытые тесты учтены в итогах, но их входы и выходы студенту не показываем
        const hidden = summary.executed - run.tests.length;
        lines.push({
          kind: summary.failed > 0 ? 'error' : 'info',
          text: `Пройдено ${summary.passed} из ${summary.planned} тестов${hidden > 0 ? ` (скрытых: ${hidden})` : ''}`,
        });
      }
      for (const test of run.tests) {
        lines.push({
          kind: test.match ? 'info' : 'error',
          text: `Тест ${test.vector_index}: din = ${test.din}, получено ${test.dout}, ожидалось ${test.expected_dout}`,
        });
      }
      if (run.mode === 'mock') {
        lines.push({
          kind: 'status',
          text: 'Демонстрационная проверка без платы, не засчитывается',
        });
      } else if (run.hardware_verified) {
        lines.push({ kind: 'info', text: 'Проверено на плате' });
      }
    }
  }

  if (isConnectionLost) {
    lines.push({ kind: 'status', text: 'Нет связи с сервером, пробуем снова...' });
  }
  return lines;
}

const useStyles = makeStyles({
  terminal: {
    flex: 1,
    minHeight: 0,
    overflowY: 'auto',
    padding: '20px 24px',
    borderRadius: tokens.borderRadiusLarge,
    backgroundColor: appTokens.terminalBackground,
    fontSize: '14px',
    lineHeight: '1.8',
  },
  title: {
    margin: '0 0 12px',
    fontSize: '14px',
    fontWeight: '600',
    color: appTokens.terminalTitle,
  },
  lines: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
  },
  info: { color: appTokens.terminalInfo },
  status: { color: appTokens.terminalStatus },
  error: { color: appTokens.terminalError },
  muted: { color: appTokens.terminalTitle },
});

interface RunLogProps {
  run: RunStatus | null;
  submitMessage: string | null;
  submitError: string | null;
  isConnectionLost: boolean;
  runError: string | null;
}

// «Терминал»: что происходит с отправленным решением, строка за строкой
export const RunLog: React.FC<RunLogProps> = ({
  run,
  submitMessage,
  submitError,
  isConnectionLost,
  runError,
}) => {
  const styles = useStyles();
  const lines = buildLines(run, submitMessage, submitError, isConnectionLost, runError);

  return (
    <div className={styles.terminal}>
      <h2 className={styles.title}>Терминал</h2>
      {/* aria-live: скринридер зачитает новые строки, когда статус изменится */}
      <ul className={styles.lines} aria-live="polite">
        {lines.map((line, index) => (
          <li key={index} className={styles[line.kind]}>
            {prefixes[line.kind] && `${prefixes[line.kind]} `}
            {line.text}
          </li>
        ))}
      </ul>
    </div>
  );
};
