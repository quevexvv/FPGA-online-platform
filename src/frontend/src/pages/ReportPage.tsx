import React from 'react';
import { Button, makeStyles, Spinner, tokens } from '@fluentui/react-components';
import { Link, useParams } from 'react-router';
import { useRunStatus } from '@/hooks/useRunStatus';
import { useSubmission } from '@/hooks/useSubmission';
import { ReportSummary } from '@/components/report/ReportSummary';

const useStyles = makeStyles({
  page: {
    height: '100%',
    boxSizing: 'border-box',
    padding: '20px 32px 32px',
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: '20px',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  topRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: '16px',
    fontSize: '13px',
    color: tokens.colorNeutralForeground2,
  },
  // Хлебные крошки: «История / Лабораторная: файл»
  breadcrumbs: {
    display: 'flex',
    gap: '8px',
    margin: 0,
    padding: 0,
    listStyle: 'none',
  },
  crumbSeparator: {
    '::before': { content: '"/"', marginRight: '8px' },
  },
  link: {
    color: tokens.colorBrandForeground1,
    textDecoration: 'none',
    ':hover': { textDecoration: 'underline' },
  },
  stateMessage: {
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    alignItems: 'center',
    gap: '12px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
    backgroundColor: tokens.colorNeutralBackground2,
  },
});

// Дата и время отправки: «23.10.2026, 14:10»
function formatDateTime(isoDate: string): string {
  return new Date(isoDate).toLocaleString('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

// Полный отчёт о проверке одной отправки: /history/:submissionId
export const ReportPage: React.FC = () => {
  const styles = useStyles();
  const { submissionId } = useParams();
  const { submission, lab, error, isNotFound, retry } = useSubmission(submissionId);
  // Тот же хук, что в рабочем пространстве: если проверка ещё идёт, отчёт обновится сам
  const { run } = useRunStatus(submissionId ?? null);

  if (isNotFound) {
    return (
      <div className={styles.stateMessage}>
        Отчёт не найден
        <Link to="/history" className={styles.link}>
          К истории проверок
        </Link>
      </div>
    );
  }
  if (error) {
    return (
      <div className={styles.stateMessage} role="alert">
        {error}
        <Button onClick={retry}>Повторить</Button>
      </div>
    );
  }
  if (!submission) {
    return (
      <div className={styles.stateMessage}>
        <Spinner label="Загружаем отчёт..." />
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <div className={styles.topRow}>
        <nav aria-label="Навигация">
          <ol className={styles.breadcrumbs}>
            <li>
              <Link to="/history" className={styles.link}>
                История
              </Link>
            </li>
            <li className={styles.crumbSeparator} aria-current="page">
              {lab ? `${lab.title}: ` : ''}student_top.v
            </li>
          </ol>
        </nav>
        <span>{formatDateTime(submission.created_at)}</span>
      </div>

      <ReportSummary run={run} />
    </div>
  );
};
