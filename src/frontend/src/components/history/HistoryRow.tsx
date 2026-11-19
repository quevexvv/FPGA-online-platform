import React, { useEffect, useState } from 'react';
import { makeStyles, mergeClasses, Spinner, tokens } from '@fluentui/react-components';
import {
  Checkmark12Filled,
  Clock12Regular,
  Dismiss12Filled,
  Info12Filled,
  Warning12Filled,
} from '@fluentui/react-icons';
import { Link } from 'react-router';
import { getSubmissionRun } from '@/api/submissions';
import { ResultTone, shortResult } from '@/components/report/reportResult';
import { HistoryItem } from '@/hooks/useHistory';
import { RunStatus } from '@/types';

const useStyles = makeStyles({
  cell: {
    padding: '24px 16px 24px 0',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    fontSize: '14px',
    color: tokens.colorNeutralForeground1,
  },
  lab: {
    fontWeight: '600',
  },
  // Бейдж статуса: цветная «таблетка» со значком
  badge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '4px',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '600',
  },
  link: {
    fontSize: '13px',
    fontWeight: '600',
    textDecoration: 'none',
    whiteSpace: 'nowrap',
    ':hover': { textDecoration: 'underline' },
  },
  muted: {
    color: tokens.colorNeutralForeground3,
  },
  // Цвета по итогу проверки: у бейджа фон и текст, у ссылки только текст
  successBadge: {
    color: tokens.colorStatusSuccessForeground1,
    backgroundColor: tokens.colorStatusSuccessBackground1,
  },
  warningBadge: {
    color: tokens.colorStatusWarningForeground1,
    backgroundColor: tokens.colorStatusWarningBackground1,
  },
  errorBadge: {
    color: tokens.colorStatusDangerForeground1,
    backgroundColor: tokens.colorStatusDangerBackground1,
  },
  infoBadge: {
    color: tokens.colorPaletteBlueForeground2,
    backgroundColor: tokens.colorPaletteBlueBackground2,
  },
  pendingBadge: {
    color: tokens.colorNeutralForeground2,
    backgroundColor: tokens.colorNeutralBackground3,
  },
  successLink: { color: tokens.colorStatusSuccessForeground1 },
  warningLink: { color: tokens.colorStatusWarningForeground1 },
  errorLink: { color: tokens.colorStatusDangerForeground1 },
  infoLink: { color: tokens.colorPaletteBlueForeground2 },
  pendingLink: { color: tokens.colorBrandForeground1 },
});

const toneIcons: Record<ResultTone, React.ReactNode> = {
  success: <Checkmark12Filled />,
  warning: <Warning12Filled />,
  error: <Dismiss12Filled />,
  info: <Info12Filled />,
  pending: <Clock12Regular />,
};

// Статус одной проверки: загружаем один раз, без опроса.
// Иначе каждая строка «в очереди» дёргала бы сервер раз в несколько секунд
function useRunOnce(submissionId: string) {
  const [state, setState] = useState<{ run: RunStatus | null; failed: boolean }>({
    run: null,
    failed: false,
  });

  useEffect(() => {
    let ignore = false;
    getSubmissionRun(submissionId)
      .then((run) => {
        if (!ignore) setState({ run, failed: false });
      })
      .catch(() => {
        if (!ignore) setState({ run: null, failed: true });
      });
    return () => {
      ignore = true;
    };
  }, [submissionId]);

  return state;
}

// «24.10.2026 18:40»
function formatDateTime(isoDate: string): string {
  return new Date(isoDate)
    .toLocaleString('ru-RU', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
    .replace(',', '');
}

// Строка таблицы истории. Статус проверки догружается сам, остальное есть сразу
export const HistoryRow: React.FC<{ item: HistoryItem }> = ({ item }) => {
  const styles = useStyles();
  const { run, failed } = useRunOnce(item.submission.id);
  const result = run ? shortResult(run) : null;
  const tone: ResultTone = result?.tone ?? 'pending';

  return (
    <tr>
      <td className={styles.cell}>{formatDateTime(item.submission.created_at)}</td>
      <td className={mergeClasses(styles.cell, styles.lab)}>{item.labTitle}: student_top.v</td>
      <td className={styles.cell}>
        {result && (
          <span className={mergeClasses(styles.badge, styles[`${tone}Badge`])}>
            {toneIcons[tone]}
            {result.title}
          </span>
        )}
        {!result && !failed && <Spinner size="extra-tiny" aria-label="Загружаем статус" />}
        {failed && <span className={styles.muted}>Статус не загрузился</span>}
      </td>
      <td className={styles.cell}>
        {run?.state === 'finished' && run.elapsed_seconds > 0 ? (
          `${Math.round(run.elapsed_seconds)} сек`
        ) : (
          <span className={styles.muted}>—</span>
        )}
      </td>
      <td className={styles.cell}>
        <Link
          to={`/history/${item.submission.id}`}
          className={mergeClasses(styles.link, styles[`${tone}Link`])}
        >
          Просмотреть полный отчёт
        </Link>
      </td>
    </tr>
  );
};
