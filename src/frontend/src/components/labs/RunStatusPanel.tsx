import React from 'react';
import {
  makeStyles,
  mergeClasses,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableHeaderCell,
  TableRow,
  tokens,
} from '@fluentui/react-components';
import { RunResult, RunStage, RunStatus } from '../../types';

// Подписи этапов проверки на стенде
const stageLabels: Record<RunStage, string> = {
  dispatch: 'Передача на стенд',
  validating: 'Проверка файлов',
  locking: 'Ожидание платы',
  building: 'Сборка',
  programming: 'Прошивка платы',
  testing: 'Тестирование',
  finalizing: 'Подведение итогов',
};

// Итоги проверки
const resultLabels: Record<RunResult, string> = {
  passed: 'Все тесты пройдены',
  mismatch: 'Есть несовпадения с ожидаемым результатом',
  build_error: 'Ошибка сборки',
  board_error: 'Не удалось завершить проверку на плате',
  invalid_input: 'Решение не принято: нарушен формат задания',
  busy: 'Стенд был занят, проверка не выполнена',
  internal_error: 'Внутренняя ошибка проверки',
};

const useStyles = makeStyles({
  panel: {
    marginTop: '16px',
    padding: '16px 20px',
    borderRadius: tokens.borderRadiusLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    backgroundColor: tokens.colorNeutralBackground2,
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground1,
  },
  // Spinner Fluent по умолчанию стоит по центру, а нам нужен у левого края
  spinner: {
    justifyContent: 'flex-start',
  },
  headline: {
    fontSize: '15px',
    fontWeight: '600',
  },
  success: {
    color: tokens.colorStatusSuccessForeground1,
  },
  failure: {
    color: tokens.colorStatusDangerForeground1,
  },
  muted: {
    color: tokens.colorNeutralForeground2,
  },
  warning: {
    color: tokens.colorStatusWarningForeground1,
  },
  code: {
    fontFamily: tokens.fontFamilyMonospace,
  },
});

interface RunStatusPanelProps {
  run: RunStatus | null;
  isConnectionLost: boolean;
  error: string | null;
}

export const RunStatusPanel: React.FC<RunStatusPanelProps> = ({ run, isConnectionLost, error }) => {
  const styles = useStyles();

  // Предупреждение о потере связи показываем под любым состоянием
  const connectionNote = isConnectionLost && (
    <div className={styles.warning} role="status">
      Нет связи с сервером, пробуем снова...
    </div>
  );

  if (error) {
    return (
      <div className={mergeClasses(styles.panel, styles.failure)} role="alert">
        {error}
      </div>
    );
  }

  if (run === null) {
    return (
      <div className={styles.panel}>
        <Spinner
          className={styles.spinner}
          size="tiny"
          label="Узнаём статус проверки..."
          labelPosition="after"
        />
        {connectionNote}
      </div>
    );
  }

  if (run.state === 'not_started') {
    return (
      <div className={styles.panel}>
        <span className={styles.muted}>Проверка этого решения не запускалась</span>
      </div>
    );
  }

  if (run.state === 'queued' || run.state === 'running') {
    const label =
      run.state === 'queued' || run.stage === null
        ? 'В очереди на проверку'
        : `Идёт проверка: ${stageLabels[run.stage]}`;
    return (
      <div className={styles.panel} aria-live="polite">
        <Spinner className={styles.spinner} size="tiny" label={label} labelPosition="after" />
        {run.state === 'running' && (
          <span className={styles.muted}>Прошло {Math.round(run.elapsed_seconds)} с</span>
        )}
        {connectionNote}
      </div>
    );
  }

  // state === 'finished': проверка закончилась, но не обязательно успешно
  const isPassed = run.result_status === 'passed';
  const summary = run.summary;
  // Скрытые тесты: их результат учтён в итогах, но сами входы и выходы студенту не показываем
  const hiddenCount = summary ? summary.executed - run.tests.length : 0;

  return (
    <div className={styles.panel} aria-live="polite">
      <span className={mergeClasses(styles.headline, isPassed ? styles.success : styles.failure)}>
        {run.result_status ? resultLabels[run.result_status] : 'Проверка завершена'}
      </span>

      {summary && summary.executed > 0 && (
        <span>
          Пройдено {summary.passed} из {summary.planned} тестов
          {hiddenCount > 0 && <span className={styles.muted}> (скрытых: {hiddenCount})</span>}
        </span>
      )}

      {run.mode === 'mock' && (
        <span className={styles.muted}>Демонстрационная проверка без платы, не засчитывается</span>
      )}
      {run.hardware_verified && <span className={styles.muted}>Проверено на плате</span>}
      {run.error && <span className={styles.muted}>{run.error.message}</span>}

      {run.tests.length > 0 && (
        <Table size="small" aria-label="Открытые тесты">
          <TableHeader>
            <TableRow>
              <TableHeaderCell>№</TableHeaderCell>
              <TableHeaderCell>Вход din</TableHeaderCell>
              <TableHeaderCell>Тактов</TableHeaderCell>
              <TableHeaderCell>Ожидалось</TableHeaderCell>
              <TableHeaderCell>Получено</TableHeaderCell>
              <TableHeaderCell>Итог</TableHeaderCell>
            </TableRow>
          </TableHeader>
          <TableBody>
            {run.tests.map((test) => (
              <TableRow key={test.vector_index}>
                <TableCell>{test.vector_index}</TableCell>
                <TableCell className={styles.code}>{test.din}</TableCell>
                <TableCell>{test.steps}</TableCell>
                <TableCell className={styles.code}>{test.expected_dout}</TableCell>
                <TableCell className={styles.code}>{test.dout}</TableCell>
                <TableCell className={test.match ? styles.success : styles.failure}>
                  {test.match ? 'Совпало' : 'Не совпало'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {connectionNote}
    </div>
  );
};