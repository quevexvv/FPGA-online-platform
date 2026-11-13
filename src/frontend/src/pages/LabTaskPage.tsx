import React from 'react';
import { Button, makeStyles, Spinner, tokens } from '@fluentui/react-components';
import { Code20Regular } from '@fluentui/react-icons';
import { Link, useParams } from 'react-router';
import { useLab } from '@/hooks/useLab';

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
  // Ссылка, которая выглядит как основная кнопка Fluent
  editorLink: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '8px',
    marginTop: '24px',
    padding: '8px 20px',
    borderRadius: tokens.borderRadiusMedium,
    fontSize: '15px',
    fontWeight: '600',
    textDecoration: 'none',
    color: tokens.colorNeutralForegroundOnBrand,
    backgroundColor: tokens.colorBrandBackground,
    ':hover': { backgroundColor: tokens.colorBrandBackgroundHover },
    ':active': { backgroundColor: tokens.colorBrandBackgroundPressed },
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

export const LabTaskPage: React.FC = () => {
  const styles = useStyles();
  // id работы берётся из адреса: /labs/:labId
  const { labId } = useParams();
  const { lab, error, isNotFound, retry } = useLab(labId);

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
            <Button onClick={retry}>Повторить</Button>
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

            {/* Решение пишется в рабочем пространстве: там редактор, отправка и ход проверки */}
            <Link to={`/workspace/${lab.id}`} className={styles.editorLink}>
              <Code20Regular />
              Открыть редактор
            </Link>
          </>
        )}
      </div>
    </div>
  );
};
