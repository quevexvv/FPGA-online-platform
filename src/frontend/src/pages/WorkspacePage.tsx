import React from 'react';
import { Button, makeStyles, mergeClasses, Spinner, tokens } from '@fluentui/react-components';
import { Link, useParams } from 'react-router';
import { useLab } from '@/hooks/useLab';
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
  },
  cardHeader: {
    padding: '16px 24px',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    fontSize: '15px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  placeholder: {
    flex: 1,
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    padding: '24px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
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

export const WorkspacePage: React.FC = () => {
  const styles = useStyles();
  // id лабораторной берётся из адреса: /workspace/:labId
  const { labId } = useParams();
  const { lab, error, isNotFound, retry } = useLab(labId);

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

  if (lab === null) {
    return (
      <div className={styles.stateMessage}>
        <Spinner label="Загружаем задание..." />
      </div>
    );
  }

  return (
    <div className={styles.page}>
      {/* Левая колонка: редактор кода */}
      <section className={styles.card} aria-label="Редактор кода">
        <div className={styles.cardHeader}>{lab.title}</div>
        <div className={styles.placeholder}>Здесь будет редактор кода</div>
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
          <div className={styles.placeholder}>Здесь будут отправка и ход проверки</div>
        </section>
      </div>
    </div>
  );
};
