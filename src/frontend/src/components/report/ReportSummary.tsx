import React from 'react';
import { makeStyles, mergeClasses, Spinner, tokens } from '@fluentui/react-components';
import { Checkmark20Filled, Dismiss20Filled, Important20Filled } from '@fluentui/react-icons';
import { RunStatus } from '@/types';
import { HardwareBadge } from './HardwareBadge';
import { describeResult, ResultTone, resultStats } from './reportResult';

const useStyles = makeStyles({
  card: {
    display: 'flex',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: '16px 40px',
    padding: '24px 32px',
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  main: {
    flex: 1,
    minWidth: '320px',
    display: 'flex',
    alignItems: 'center',
    gap: '16px',
  },
  // Круглый значок слева: цвет зависит от итога
  icon: {
    flexShrink: 0,
    width: '40px',
    height: '40px',
    borderRadius: '50%',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
  },
  success: {
    color: tokens.colorStatusSuccessForeground1,
    backgroundColor: tokens.colorStatusSuccessBackground1,
  },
  warning: {
    color: tokens.colorStatusWarningForeground1,
    backgroundColor: tokens.colorStatusWarningBackground1,
  },
  error: {
    color: tokens.colorStatusDangerForeground1,
    backgroundColor: tokens.colorStatusDangerBackground1,
  },
  info: {
    color: tokens.colorPaletteBlueForeground2,
    backgroundColor: tokens.colorPaletteBlueBackground2,
  },
  pending: {
    backgroundColor: tokens.colorNeutralBackground3,
  },
  titleRow: {
    display: 'flex',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: '8px 12px',
  },
  title: {
    margin: 0,
    fontSize: '20px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  description: {
    margin: '6px 0 0',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
  // Числа справа: подпись маленькими заглавными, значение крупно
  stats: {
    display: 'flex',
    gap: '32px',
    margin: 0,
  },
  statLabel: {
    fontSize: '11px',
    fontWeight: '600',
    textTransform: 'uppercase',
    color: tokens.colorNeutralForeground2,
  },
  statValue: {
    margin: '4px 0 0',
    fontSize: '18px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
});

const toneIcons: Record<ResultTone, React.ReactNode> = {
  success: <Checkmark20Filled />,
  warning: <Important20Filled />,
  error: <Dismiss20Filled />,
  info: <Important20Filled />,
  pending: <Spinner size="tiny" />,
};

// Карточка итога наверху отчёта: что случилось и главные числа
export const ReportSummary: React.FC<{ run: RunStatus | null }> = ({ run }) => {
  const styles = useStyles();
  const result = describeResult(run);
  const stats = resultStats(run);

  return (
    // aria-live: пока проверка идёт, итог меняется сам, и скринридер об этом скажет
    <section className={styles.card} aria-label="Итог проверки" aria-live="polite">
      <div className={styles.main}>
        <span className={mergeClasses(styles.icon, styles[result.tone])} aria-hidden>
          {toneIcons[result.tone]}
        </span>
        <div>
          <div className={styles.titleRow}>
            <h1 className={styles.title}>{result.title}</h1>
            <HardwareBadge run={run} />
          </div>
          {result.description && <p className={styles.description}>{result.description}</p>}
        </div>
      </div>

      {stats.length > 0 && (
        // Список «подпись — значение» в HTML — это <dl>: <dt> подпись, <dd> значение
        <dl className={styles.stats}>
          {stats.map((stat) => (
            <div key={stat.label}>
              <dt className={styles.statLabel}>{stat.label}</dt>
              <dd className={styles.statValue}>{stat.value}</dd>
            </div>
          ))}
        </dl>
      )}
    </section>
  );
};
