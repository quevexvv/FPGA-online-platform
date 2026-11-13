import React, { useEffect, useState } from 'react';
import { Button, makeStyles, Spinner, Textarea, tokens } from '@fluentui/react-components';
import { Link, useParams } from 'react-router';
import { getLab } from '@/api/labs';
import { submitSolution } from '@/api/submissions';
import { ApiError } from '@/api/client';
import { LabDetail } from '@/types';
import { useRunStatus } from '@/hooks/useRunStatus';
import { RunStatusPanel } from '@/components/labs/RunStatusPanel';

const useStyles = makeStyles({
  pageContainer: {
    padding: '24px 32px',
    height: '100%',
    boxSizing: 'border-box',
    overflowY: 'auto',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  card: {
    maxWidth: '960px',
    margin: '0 auto',
    padding: '24px 32px 32px',
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  backLink: {
    textDecoration: 'none',
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorBrandForeground1,
  },
  title: {
    margin: '16px 0 0',
    fontSize: '20px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  description: {
    margin: '4px 0 0',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
  sectionTitle: {
    margin: '24px 0 8px',
    fontSize: '16px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  text: {
    margin: 0,
    fontSize: '14px',
    lineHeight: '1.6',
    color: tokens.colorNeutralForeground1,
    // Сохраняем переносы строк, которые преподаватель поставил в тексте
    whiteSpace: 'pre-wrap',
  },
  codeField: {
    width: '100%',
  },
  codeInput: {
    minHeight: '320px',
    maxHeight: 'none',
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: '13px',
    lineHeight: '1.5',
  },
  submitRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '16px',
    marginTop: '16px',
  },
  submitSuccess: {
    fontSize: '14px',
    color: tokens.colorStatusSuccessForeground1,
  },
  submitError: {
    fontSize: '14px',
    color: tokens.colorPaletteRedForeground1,
  },
  // Загрузка и ошибки: сообщение по центру карточки
  stateMessage: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '12px',
    padding: '48px 0 16px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
});

// Содержимое страницы задания. labId приходит от LabTaskPage ниже
const LabTaskContent: React.FC<{ labId: string | undefined }> = ({ labId }) => {
  const styles = useStyles();

  // null — данные ещё не пришли
  const [lab, setLab] = useState<LabDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reloadCount, setReloadCount] = useState(0);
  // Ошибку «не найдено» показываем без кнопки «Повторить»: повтор не поможет
  const [isNotFound, setIsNotFound] = useState(false);

  // Код решения и состояние отправки
  const [code, setCode] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitMessage, setSubmitMessage] = useState<string | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);

  // Последняя отправка в этом окне: за её проверкой и следим
  const [submissionId, setSubmissionId] = useState<string | null>(null);
  const runStatus = useRunStatus(submissionId);

  useEffect(() => {
    if (!labId) return;

    let ignore = false;
    
    getLab(labId)
      .then((data) => {
        if (ignore) return;
        setLab(data);
        // Студент начинает с шаблона, который дал преподаватель
        setCode(data.template);

      })
      .catch((err) => {
        if (ignore) return;
        // 404 — такой работы нет, 422 — в адресе вообще не UUID
        if (err instanceof ApiError && (err.status === 404 || err.status === 422)) {
          setIsNotFound(true);
        } else {
          setError('Не удалось загрузить задание');
        }
      });

    return () => {
      ignore = true;
    };
  }, [labId, reloadCount]);

  // Повтор после ошибки: убираем ошибку (появится загрузка) и запускаем эффект заново
  const handleRetry = () => {
    setError(null);
    setReloadCount((count) => count + 1);
  };

  const handleSubmit = async () => {
    if (!labId) return;
    setIsSubmitting(true);
    setSubmitMessage(null);
    setSubmitError(null);
    try {
      const submission = await submitSolution(labId, code);
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
    <div className={styles.pageContainer}>
      <div className={styles.card}>
        <Link to="/labs" className={styles.backLink}>
          ←&nbsp;К списку лабораторных
        </Link>

        {isNotFound || !labId ? (
          <div className={styles.stateMessage}>Лабораторная не найдена</div>
        ) : error ? (
          <div className={styles.stateMessage} role="alert">
            {error}
            <Button onClick={handleRetry}>Повторить</Button>
          </div>
        ) : lab === null ? (
          <div className={styles.stateMessage}>
            <Spinner label="Загружаем задание..." />
          </div>
        ) : (
          <>
            <h1 className={styles.title}>{lab.title}</h1>
            <p className={styles.description}>{lab.description}</p>

            <h2 className={styles.sectionTitle}>Условие</h2>
            <p className={styles.text}>{lab.statement}</p>

            <h2 className={styles.sectionTitle}>Интерфейс модуля</h2>
            <p className={styles.text}>{lab.interface_description}</p>

            <h2 className={styles.sectionTitle}>Решение</h2>
            <Textarea
              className={styles.codeField}
              textarea={{ className: styles.codeInput, spellCheck: false }}
              resize="vertical"
              aria-label="Код решения на Verilog"
              value={code}
              onChange={(_, data) => {
                setCode(data.value);
                // Код изменился — прошлое сообщение об отправке уже не про него
                setSubmitMessage(null);
              }}
            />

            <div className={styles.submitRow}>
              <Button
                appearance="primary"
                onClick={handleSubmit}
                disabled={isSubmitting || code.trim() === ''}
              >
                {isSubmitting ? 'Отправляем...' : 'Отправить решение'}
              </Button>
              {submitMessage && (
                <span className={styles.submitSuccess} role="status">
                  {submitMessage}
                </span>
              )}
              {submitError && (
                <span className={styles.submitError} role="alert">
                  {submitError}
                </span>
              )}
            </div>
            {submissionId && (
              <RunStatusPanel
                run={runStatus.run}
                isConnectionLost={runStatus.isConnectionLost}
                error={runStatus.error}
              />
            )}
          </>
        )}
      </div>
    </div>
  );
};

export const LabTaskPage: React.FC = () => {
  // id работы берётся из адреса: /labs/:labId
  const { labId } = useParams();
  // key: при переходе к другой лабораторной React создаёт содержимое заново,
  // и всё состояние (задание, код, статус отправки) начинается с чистого листа
  return <LabTaskContent key={labId} labId={labId} />;
};