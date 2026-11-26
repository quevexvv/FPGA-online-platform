import React from 'react';
import { Button, makeStyles, Spinner, tokens } from '@fluentui/react-components';
import { Link } from 'react-router';
import { HistoryRow } from '@/components/history/HistoryRow';
import { useHistory } from '@/hooks/useHistory';

const useStyles = makeStyles({
  page: {
    height: '100%',
    boxSizing: 'border-box',
    padding: '16px',
    overflowY: 'auto',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  card: {
    boxSizing: 'border-box',
    minHeight: '100%',
    padding: '28px 36px',
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  title: {
    margin: '0 0 24px',
    fontSize: '20px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  // Широкая таблица на узком экране прокручивается внутри карточки
  scroll: {
    overflowX: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
  },
  headCell: {
    padding: '0 16px 14px 0',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    textAlign: 'left',
    whiteSpace: 'nowrap',
    fontSize: '12px',
    fontWeight: '600',
    textTransform: 'uppercase',
    color: tokens.colorNeutralForeground2,
  },
  message: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '12px',
    padding: '64px 0',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
  link: {
    color: tokens.colorBrandForeground1,
    fontWeight: '600',
    textDecoration: 'none',
  },
});

// История: все отправки студента со статусом проверки и ссылкой на полный отчёт
export const HistoryPage: React.FC = () => {
  const styles = useStyles();
  const { items, error, retry } = useHistory();

  let content: React.ReactNode;
  if (error) {
    content = (
      <div className={styles.message} role="alert">
        {error}
        <Button onClick={retry}>Повторить</Button>
      </div>
    );
  } else if (items === null) {
    content = (
      <div className={styles.message}>
        <Spinner label="Загружаем историю..." />
      </div>
    );
  } else if (items.length === 0) {
    content = (
      <div className={styles.message}>
        Вы ещё не отправляли решений
        <Link to="/labs" className={styles.link}>
          К списку лабораторных
        </Link>
      </div>
    );
  } else {
    content = (
      <div className={styles.scroll}>
        <table className={styles.table}>
          <thead>
            <tr>
              <th className={styles.headCell}>Дата и время</th>
              <th className={styles.headCell}>Лабораторная: файл</th>
              <th className={styles.headCell}>Статус проверки</th>
              <th className={styles.headCell}>Время проверки</th>
              <th className={styles.headCell}>Действия</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <HistoryRow key={item.submission.id} item={item} />
            ))}
          </tbody>
        </table>
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <section className={styles.card} aria-labelledby="history-title">
        <h1 id="history-title" className={styles.title}>
          История запусков и проверок
        </h1>
        {content}
      </section>
    </div>
  );
};
