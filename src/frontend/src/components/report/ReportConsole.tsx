import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { appTokens } from '@/theme/themes';
import { RunStatus } from '@/types';
import { describeResult, resultStats } from './reportResult';

const useStyles = makeStyles({
  title: {
    margin: '0 0 16px',
    fontSize: '16px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  terminal: {
    flex: 1,
    minHeight: '200px',
    margin: 0,
    padding: '16px 20px',
    overflowY: 'auto',
    borderRadius: tokens.borderRadiusLarge,
    backgroundColor: appTokens.terminalBackground,
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: '13px',
    lineHeight: '1.8',
    listStyle: 'none',
  },
  line: { color: tokens.colorNeutralForeground1 },
  muted: { color: appTokens.terminalTitle },
  bad: { color: appTokens.terminalError },
  result: { fontWeight: '700', color: appTokens.terminalStatus },
  passed: { fontWeight: '700', color: appTokens.terminalInfo },
  gap: { height: '12px' },
});

// Консоль отчёта: строка на каждый открытый тест и итоги.
// TODO: логи сборки и прошивки появятся, когда их начнёт отдавать сервер
export const ReportConsole: React.FC<{ run: RunStatus | null; className?: string }> = ({
  run,
  className,
}) => {
  const styles = useStyles();
  const isFinished = run?.state === 'finished';
  const result = describeResult(run);

  return (
    <section className={className} aria-labelledby="report-console-title">
      <h2 id="report-console-title" className={styles.title}>
        Консоль
      </h2>
      <ul className={styles.terminal}>
        {!isFinished && <li className={styles.muted}>Результаты появятся после проверки</li>}
        {isFinished &&
          run.tests.map((test) => (
            <li key={test.vector_index} className={test.match ? styles.line : styles.bad}>
              Тест {test.vector_index + 1} din={test.din} dout={test.dout} ожидалось=
              {test.expected_dout} {test.match ? 'совпало' : 'не совпало'}
            </li>
          ))}
        {isFinished && run.error && <li className={styles.bad}>{run.error.message}</li>}
        {isFinished && (
          <>
            <li className={styles.gap} aria-hidden />
            {resultStats(run).map((stat) => (
              <li key={stat.label} className={styles.muted}>
                {stat.label}: {stat.value}
              </li>
            ))}
            <li className={mergeClasses(result.tone === 'success' ? styles.passed : styles.result)}>
              Итог: {result.title.toLowerCase()}
            </li>
          </>
        )}
      </ul>
    </section>
  );
};
