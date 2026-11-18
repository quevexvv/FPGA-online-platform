import React from 'react';
import { makeStyles, tokens } from '@fluentui/react-components';
import { FpgaBoard } from '@/components/board/FpgaBoard';
import {
  boardStateFromTest,
  isBitSet,
  isLedMismatch,
  ledColors,
  leds,
  MISMATCH_COLOR,
} from '@/components/board/boardLayout';
import { appTokens } from '@/theme/themes';
import { RunStatus, RunTest } from '@/types';
import { HardwareBadge } from './HardwareBadge';

const useStyles = makeStyles({
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: '12px',
  },
  title: {
    margin: 0,
    fontSize: '16px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  board: {
    flex: 1,
    minHeight: 0,
    maxHeight: '420px',
    margin: '16px 0',
  },
  footer: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: '8px 24px',
  },
  legend: {
    display: 'flex',
    gap: '20px',
    margin: 0,
    padding: 0,
    listStyle: 'none',
    fontSize: '13px',
    color: tokens.colorNeutralForeground2,
  },
  legendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  },
  mismatchText: {
    margin: 0,
    fontSize: '13px',
    fontWeight: '600',
    color: appTokens.stepFailed,
  },
});

// Маленький светодиод для легенды: такой же, как на плате
const LegendLed: React.FC<{ fill: string; frame?: boolean }> = ({ fill, frame = false }) => (
  <svg width="16" height="20" viewBox="0 0 16 20" aria-hidden>
    <rect x="4.5" y="4.5" width="7" height="11" fill={fill} stroke="white" />
    {frame && (
      <rect
        x="0.75"
        y="0.75"
        width="14.5"
        height="18.5"
        rx="3.5"
        fill="none"
        stroke={MISMATCH_COLOR}
        strokeWidth="1.5"
      />
    )}
  </svg>
);

// Что не совпало: «LEDR3: ожидалось 1, получено 0»
function mismatchDetails(test: RunTest): string {
  const state = boardStateFromTest(test);
  return leds
    .filter((led) => isLedMismatch(state, led))
    .map(
      (led) =>
        `${led.name}: ожидалось ${isBitSet(state.expected, led.bit) ? 1 : 0}, ` +
        `получено ${isBitSet(state.dout, led.bit) ? 1 : 0}`,
    )
    .join('; ');
}

interface ReportBoardProps {
  run: RunStatus | null;
  test: RunTest | null; // выбранный тест; null — тестов нет
  className?: string;
}

// Карточка с платой в отчёте: выбранный тест, легенда и что не совпало
export const ReportBoard: React.FC<ReportBoardProps> = ({ run, test, className }) => {
  const styles = useStyles();
  const details = test ? mismatchDetails(test) : '';

  return (
    <section className={className} aria-labelledby="report-board-title">
      <div className={styles.header}>
        <h2 id="report-board-title" className={styles.title}>
          {test ? `Результат на плате: тест ${test.vector_index + 1}` : 'Результат на плате'}
        </h2>
        <HardwareBadge run={run} />
      </div>

      <FpgaBoard className={styles.board} state={test ? boardStateFromTest(test) : null} />

      <div className={styles.footer}>
        <ul className={styles.legend} aria-label="Обозначения">
          <li className={styles.legendItem}>
            <LegendLed fill={ledColors.red.on} />
            Горит
          </li>
          <li className={styles.legendItem}>
            <LegendLed fill={ledColors.red.off} />
            Погашен
          </li>
          <li className={styles.legendItem}>
            <LegendLed fill={ledColors.red.off} frame />
            Расхождение
          </li>
        </ul>
        {details && <p className={styles.mismatchText}>{details}</p>}
      </div>
    </section>
  );
};
