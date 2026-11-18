import React, { useState } from 'react';
import {
  Button,
  makeStyles,
  mergeClasses,
  Spinner,
  Tab,
  TabList,
  tokens,
} from '@fluentui/react-components';
import { Link, useParams } from 'react-router';
import { useRunStatus } from '@/hooks/useRunStatus';
import { useSubmission } from '@/hooks/useSubmission';
import { CodeEditor } from '@/components/workspace/CodeEditor';
import { OpenTestsTable } from '@/components/report/OpenTestsTable';
import { ReportBoard } from '@/components/report/ReportBoard';
import { ReportConsole } from '@/components/report/ReportConsole';
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
  card: {
    boxSizing: 'border-box',
    padding: '24px 28px',
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    display: 'flex',
    flexDirection: 'column',
    minWidth: 0,
  },
  // Слева таблица и консоль, справа плата на всю высоту
  grid: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)',
    gridTemplateAreas: '"tests board" "console board"',
    gap: '24px',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: 'minmax(0, 1fr)',
      gridTemplateAreas: '"tests" "board" "console"',
    },
  },
  tests: { gridArea: 'tests' },
  board: { gridArea: 'board' },
  console: { gridArea: 'console' },
  cardHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    flexWrap: 'wrap',
    gap: '8px 16px',
    marginBottom: '16px',
  },
  cardTitle: {
    margin: 0,
    fontSize: '16px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  hint: {
    fontSize: '12px',
    color: tokens.colorNeutralForeground2,
  },
  empty: {
    margin: 0,
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
  codeCard: {
    height: '560px',
    padding: 0,
    overflow: 'hidden',
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

type ReportTab = 'report' | 'code';

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
  const [tab, setTab] = useState<ReportTab>('report');
  // Выбранный тест. Пока не выбран, показываем первый непройденный
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);

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

  const tests = run?.state === 'finished' ? run.tests : [];
  const firstFailed = tests.findIndex((test) => !test.match);
  const testIndex = selectedIndex ?? (firstFailed === -1 ? 0 : firstFailed);
  const test = tests[testIndex] ?? null;

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

      <TabList selectedValue={tab} onTabSelect={(_, data) => setTab(data.value as ReportTab)}>
        <Tab value="report">Отчёт</Tab>
        <Tab value="code">Код попытки</Tab>
      </TabList>

      {tab === 'report' && (
        <div className={styles.grid}>
          <section
            className={mergeClasses(styles.card, styles.tests)}
            aria-labelledby="report-tests-title"
          >
            <div className={styles.cardHeader}>
              <h2 id="report-tests-title" className={styles.cardTitle}>
                Открытые примеры
              </h2>
              {tests.length > 0 && (
                <span className={styles.hint}>Выберите строку, чтобы увидеть её на плате</span>
              )}
            </div>
            {tests.length > 0 ? (
              <OpenTestsTable tests={tests} selectedIndex={testIndex} onSelect={setSelectedIndex} />
            ) : (
              <p className={styles.empty}>
                {run?.state === 'finished'
                  ? 'Открытые примеры не запускались'
                  : 'Появятся, когда проверка закончится'}
              </p>
            )}
          </section>

          <ReportBoard className={mergeClasses(styles.card, styles.board)} run={run} test={test} />
          <ReportConsole className={mergeClasses(styles.card, styles.console)} run={run} />
        </div>
      )}

      {tab === 'code' && (
        <section className={mergeClasses(styles.card, styles.codeCard)} aria-label="Код попытки">
          <CodeEditor
            initialValue={submission.source_code}
            ariaLabel="Код отправленного решения, только чтение"
            readOnly
          />
        </section>
      )}
    </div>
  );
};
