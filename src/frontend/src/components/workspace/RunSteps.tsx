import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { Checkmark16Filled, Dismiss16Filled } from '@fluentui/react-icons';
import { appTokens } from '@/theme/themes';
import { StepState, steps } from './runProgress';

const useStyles = makeStyles({
  list: {
    display: 'flex',
    margin: 0,
    padding: 0,
    listStyle: 'none',
  },
  // Каждый шаг — три строки: подпись сверху, кружок, подпись снизу.
  // Подписи чередуются сверху и снизу, чтобы длинные слова не налезали друг на друга
  step: {
    flex: 1,
    minWidth: 0,
    display: 'grid',
    // Одна колонка ровно по ширине шага: длинная подпись выходит за края поровну с двух сторон
    gridTemplateColumns: 'minmax(0, 1fr)',
    gridTemplateRows: '18px 28px 18px',
    rowGap: '8px',
    justifyItems: 'center',
    alignItems: 'center',
    position: 'relative',
    // Линия к предыдущему шагу: от центра этого кружка до центра прошлого
    '::before': {
      content: '""',
      position: 'absolute',
      top: '39px',
      right: '50%',
      width: '100%',
      height: '2px',
      backgroundColor: appTokens.stepLine,
    },
    ':first-child::before': { display: 'none' },
  },
  // Линия до пройденного шага зелёная
  stepReached: {
    '::before': { backgroundColor: appTokens.stepDone },
  },
  circle: {
    gridRow: '2',
    position: 'relative',
    zIndex: 1,
    width: '28px',
    height: '28px',
    borderRadius: '50%',
    boxSizing: 'border-box',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    fontSize: '12px',
    fontWeight: '600',
    color: appTokens.stepPendingText,
    backgroundColor: appTokens.stepPending,
  },
  circleDone: {
    color: tokens.colorNeutralForegroundOnBrand,
    backgroundColor: appTokens.stepDone,
  },
  // Текущий шаг: оранжевое кольцо с точкой внутри
  circleCurrent: {
    border: `3px solid ${appTokens.stepCurrent}`,
    backgroundColor: tokens.colorNeutralBackground1,
    '::after': {
      content: '""',
      width: '12px',
      height: '12px',
      borderRadius: '50%',
      backgroundColor: appTokens.stepCurrent,
    },
  },
  circleFailed: {
    color: tokens.colorNeutralForegroundOnBrand,
    backgroundColor: appTokens.terminalError,
  },
  label: {
    whiteSpace: 'nowrap',
    fontSize: '13px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground2,
  },
  labelTop: { gridRow: '1' },
  labelBottom: { gridRow: '3' },
  labelDone: { color: tokens.colorNeutralForeground1 },
  labelCurrent: { color: appTokens.stepCurrent },
  labelFailed: { color: appTokens.terminalError },
});

interface RunStepsProps {
  states: StepState[];
}

// Шаги проверки: очередь → проверка файлов → сборка → прошивка → тесты → завершение
export const RunSteps: React.FC<RunStepsProps> = ({ states }) => {
  const styles = useStyles();

  return (
    <ol className={styles.list} aria-label="Ход проверки">
      {steps.map((label, index) => {
        const state = states[index];
        return (
          <li
            key={label}
            className={mergeClasses(styles.step, state !== 'pending' && styles.stepReached)}
            aria-current={state === 'current' ? 'step' : undefined}
          >
            <span
              className={mergeClasses(
                styles.circle,
                state === 'done' && styles.circleDone,
                state === 'current' && styles.circleCurrent,
                state === 'failed' && styles.circleFailed,
              )}
              aria-hidden
            >
              {state === 'done' && <Checkmark16Filled />}
              {state === 'failed' && <Dismiss16Filled />}
              {state === 'pending' && index + 1}
            </span>
            <span
              className={mergeClasses(
                styles.label,
                // Чётные шаги подписаны сверху, нечётные — снизу
                index % 2 === 0 ? styles.labelTop : styles.labelBottom,
                state === 'done' && styles.labelDone,
                state === 'current' && styles.labelCurrent,
                state === 'failed' && styles.labelFailed,
              )}
            >
              {label}
            </span>
          </li>
        );
      })}
    </ol>
  );
};
