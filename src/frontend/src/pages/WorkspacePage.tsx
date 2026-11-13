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
import { Play20Filled } from '@fluentui/react-icons';
import { Link, useParams } from 'react-router';
import { ApiError } from '@/api/client';
import { submitSolution } from '@/api/submissions';
import { useLab } from '@/hooks/useLab';
import { useLatestSubmission } from '@/hooks/useLatestSubmission';
import { useRunStatus } from '@/hooks/useRunStatus';
import { CodeEditor } from '@/components/workspace/CodeEditor';
import { RunLog } from '@/components/workspace/RunLog';
import { RunSteps } from '@/components/workspace/RunSteps';
import { getStepStates } from '@/components/workspace/runProgress';
import { LabDetail, SubmissionDetail } from '@/types';
import boardImage from '@/assets/fpga-board.svg';

const useStyles = makeStyles({
  // Две колонки: слева редактор, справа плата и проверка
  page: {
    height: '100%',
    boxSizing: 'border-box',
    padding: '24px 32px',
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)',
    gap: '24px',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  card: {
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    boxSizing: 'border-box',
    // Без minHeight: 0 содержимое растянуло бы карточку выше экрана вместо прокрутки
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  rightColumn: {
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
    gap: '24px',
  },
  boardCard: {
    flexShrink: 0,
    padding: '16px',
    alignItems: 'center',
  },
  boardImage: {
    display: 'block',
    width: '100%',
    // Плата уменьшается вместе с окном, но не растягивается выше 360px
    maxHeight: '360px',
    objectFit: 'contain',
  },
  checkCard: {
    flex: 1,
    padding: '20px 24px',
    gap: '20px',
  },
  // Кнопка отправки и шаги проверки в одну строку, как на макете
  checkHeader: {
    flexShrink: 0,
    display: 'flex',
    alignItems: 'center',
    gap: '32px',
  },
  submitButton: {
    flexShrink: 0,
    minWidth: '240px',
  },
  steps: {
    flex: 1,
    minWidth: 0,
  },
  tabs: {
    flexShrink: 0,
    padding: '4px 12px 0',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  editorWrapper: {
    flex: 1,
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
  },
  hidden: {
    display: 'none',
  },
  // Вкладка с заданием: условие и интерфейс прокручиваются, если не помещаются
  taskText: {
    flex: 1,
    minHeight: 0,
    overflowY: 'auto',
    padding: '8px 24px 24px',
  },
  sectionTitle: {
    margin: '16px 0 8px',
    fontSize: '15px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  text: {
    margin: 0,
    fontSize: '14px',
    lineHeight: '1.6',
    color: tokens.colorNeutralForeground1,
    whiteSpace: 'pre-wrap',
  },
  // Сообщение на всю страницу: загрузка, ошибка, лабораторная не выбрана
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
  link: {
    color: tokens.colorBrandForeground1,
    fontWeight: '600',
    textDecoration: 'none',
  },
});

type EditorTab = 'code' | 'task';

// Время от сервера в UTC показываем в часовом поясе пользователя
function formatTime(isoDate: string): string {
  return new Date(isoDate).toLocaleString('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

interface WorkspaceContentProps {
  lab: LabDetail;
  // Последнее отправленное решение, если оно есть: с него и продолжаем
  lastSubmission: SubmissionDetail | null;
}

// Рабочее пространство для уже загруженной лабораторной
const WorkspaceContent: React.FC<WorkspaceContentProps> = ({ lab, lastSubmission }) => {
  const styles = useStyles();
  const [tab, setTab] = useState<EditorTab>('code');
  // Продолжаем с последнего отправленного кода, а если отправок не было — с шаблона
  const initialCode = lastSubmission?.source_code ?? lab.template;
  const [code, setCode] = useState(lab.template);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitMessage, setSubmitMessage] = useState<string | null>(
    lastSubmission ? `Последняя отправка: ${formatTime(lastSubmission.created_at)}` : null,
  );
  const [submitError, setSubmitError] = useState<string | null>(null);
  // Последняя отправка: за её проверкой и следим
  const [submissionId, setSubmissionId] = useState<string | null>(lastSubmission?.id ?? null);
  const runStatus = useRunStatus(submissionId);

  const handleSubmit = async () => {
    setIsSubmitting(true);
    setSubmitMessage(null);
    setSubmitError(null);
    try {
      const submission = await submitSolution(lab.id, code);
      // Время от сервера в UTC, показываем в часовом поясе пользователя
      const time = new Date(submission.created_at).toLocaleTimeString('ru-RU', {
        hour: '2-digit',
        minute: '2-digit',
      });
      setSubmitMessage(`Решение отправлено в ${time}`);
      setSubmissionId(submission.id);
    } catch (err) {
      if (err instanceof ApiError && err.status === 403) {
        setSubmitError('Отправлять решения могут только студенты');
      } else if (err instanceof ApiError && err.status === 422) {
        setSubmitError('Код не принят: он пустой или больше 64 КБ');
      } else {
        setSubmitError('Не удалось отправить решение. Попробуйте ещё раз');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className={styles.page}>
      {/* Левая колонка: код и задание во вкладках */}
      <section className={styles.card} aria-label="Редактор кода">
        <TabList
          className={styles.tabs}
          selectedValue={tab}
          onTabSelect={(_, data) => setTab(data.value as EditorTab)}
        >
          <Tab value="code">student_top.v</Tab>
          <Tab value="task">Задание</Tab>
        </TabList>

        {/* Редактор только прячем, а не убираем: так не теряются курсор и история отмены */}
        <div className={tab === 'code' ? styles.editorWrapper : styles.hidden}>
          <CodeEditor
            initialValue={initialCode}
            onChange={setCode}
            ariaLabel="Код решения на Verilog"
          />
        </div>

        {tab === 'task' && (
          <div className={styles.taskText}>
            <h2 className={styles.sectionTitle}>{lab.title}</h2>
            <p className={styles.text}>{lab.statement}</p>
            <h2 className={styles.sectionTitle}>Интерфейс модуля</h2>
            <p className={styles.text}>{lab.interface_description}</p>
          </div>
        )}
      </section>

      {/* Правая колонка: плата и проверка */}
      <div className={styles.rightColumn}>
        <section className={mergeClasses(styles.card, styles.boardCard)} aria-label="Плата">
          <img className={styles.boardImage} src={boardImage} alt="Отладочная плата с ПЛИС" />
        </section>

        <section
          className={mergeClasses(styles.card, styles.checkCard)}
          aria-label="Проверка решения"
        >
          <div className={styles.checkHeader}>
            <Button
              className={styles.submitButton}
              appearance="primary"
              size="large"
              icon={<Play20Filled />}
              onClick={handleSubmit}
              disabled={isSubmitting || code.trim() === ''}
            >
              {isSubmitting ? 'Отправляем...' : 'Отправить на проверку'}
            </Button>
            <div className={styles.steps}>
              <RunSteps states={getStepStates(runStatus.run)} />
            </div>
          </div>

          <RunLog
            run={runStatus.run}
            submitMessage={submitMessage}
            submitError={submitError}
            isConnectionLost={runStatus.isConnectionLost}
            runError={runStatus.error}
          />
        </section>
      </div>
    </div>
  );
};

export const WorkspacePage: React.FC = () => {
  const styles = useStyles();
  // id лабораторной берётся из адреса: /workspace/:labId
  const { labId } = useParams();
  const { lab, error, isNotFound, retry } = useLab(labId);
  const latest = useLatestSubmission(labId);

  // Рабочее пространство открыли из шапки, без выбранной лабораторной
  if (!labId) {
    return (
      <div className={styles.stateMessage}>
        Выберите лабораторную, чтобы начать работу
        <Link to="/labs" className={styles.link}>
          К списку лабораторных
        </Link>
      </div>
    );
  }

  if (isNotFound) {
    return <div className={styles.stateMessage}>Лабораторная не найдена</div>;
  }

  if (error) {
    return (
      <div className={styles.stateMessage} role="alert">
        {error}
        <Button onClick={retry}>Повторить</Button>
      </div>
    );
  }

  // Ждём и задание, и последнюю отправку: от неё зависит, с какого кода начать
  if (lab === null || !latest.isLoaded) {
    return (
      <div className={styles.stateMessage}>
        <Spinner label="Загружаем задание..." />
      </div>
    );
  }

  // key: при переходе к другой лабораторной содержимое создаётся заново
  return <WorkspaceContent key={lab.id} lab={lab} lastSubmission={latest.submission} />;
};
