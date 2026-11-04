import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { mockLabs } from '../mockLabs';
import { LabItem } from '../types';

const useStyles = makeStyles({
  pageContainer: {
    padding: '24px 32px',
    height: '100%',
    boxSizing: 'border-box',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  mainCard: {
    width: '100%',
    flex: 1,
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  titleContainer: {
    padding: '24px 32px 16px 32px',
    flexShrink: 0,
  },
  title: {
    fontSize: '20px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
    margin: 0,
  },
  tableHeader: {
    display: 'grid',
    gridTemplateColumns: '2fr 2fr 1.5fr 1fr 1fr',
    padding: '12px 32px',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    fontSize: '12px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground2,
    letterSpacing: '0.5px',
    flexShrink: 0,
  },
  tableScrollBody: {
    flex: 1,
    overflowY: 'auto',
    padding: '0 32px',
    // Кастомный скроллбар для надежности
    scrollbarWidth: 'thin',
    scrollbarColor: `${tokens.colorNeutralStroke1} transparent`,
  },
  row: {
    display: 'grid',
    gridTemplateColumns: '2fr 2fr 1.5fr 1fr 1fr',
    padding: '20px 0',
    alignItems: 'center',
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
  labTitle: {
    fontWeight: '700',
    fontSize: '15px',
    color: tokens.colorNeutralForeground1,
  },
  labSubtitle: {
    fontSize: '13px',
    color: tokens.colorNeutralForeground2,
    marginTop: '4px',
  },
  description: {
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
  badgeCompleted: {
    display: 'inline-flex',
    alignItems: 'center',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
    backgroundColor: 'rgba(0, 140, 58, 0.15)',
    color: tokens.colorBrandBackground,
    width: 'fit-content',
  },
  badgeInProgress: {
    display: 'inline-flex',
    alignItems: 'center',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
    backgroundColor: 'rgba(217, 119, 6, 0.15)',
    color: '#D97706',
    width: 'fit-content',
  },
  badgeNotStarted: {
    display: 'inline-flex',
    alignItems: 'center',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
    backgroundColor: tokens.colorNeutralStroke3,
    color: tokens.colorNeutralForeground2,
    width: 'fit-content',
  },
  actionButton: {
  background: 'none',
  border: 'none',
  padding: 0,
  fontFamily: 'inherit',
  fontSize: '14px',
  fontWeight: '600',
  cursor: 'pointer',
},
  actionGreen: {
    color: tokens.colorBrandBackground,
},
  actionOrange: {
    color: '#D97706',
},
  actionBlocked: {
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground2,
  },
});

interface LabsPageProps {
  onOpenTask: () => void;
  onOpenCode: () => void;
}

export const LabsPage: React.FC<LabsPageProps> = ({ onOpenTask, onOpenCode }) => {
  const styles = useStyles();

  const renderStatus = (status: LabItem['status']) => {
    switch (status) {
      case 'completed':
        return <span className={styles.badgeCompleted}>Выполнено</span>;
      case 'in_progress':
        return <span className={styles.badgeInProgress}>В работе</span>;
      case 'not_started':
        return <span className={styles.badgeNotStarted}>Не начато</span>;
    }
  };

  const renderDeadline = (lab: LabItem) => {
    if (lab.deadlineType === 'today') {
      return <span style={{ color: '#D97706', fontWeight: 600 }}>{lab.deadline}</span>;
    }
    if (lab.deadlineType === 'completed') {
      return <span style={{ color: tokens.colorBrandBackground, fontWeight: 600 }}>{lab.deadline}</span>;
    }
    return <span>{lab.deadline}</span>;
  };

  const renderAction = (lab: LabItem) => {
  if (lab.isLocked) {
    return <span className={styles.actionBlocked}>Заблокировано</span>;
  }
  if (lab.status === 'completed') {
    return (
      <button
        type="button"
        className={mergeClasses(styles.actionButton, styles.actionGreen)}
        onClick={onOpenCode}
      >
        Посмотреть код →
      </button>
    );
  }
  return (
    <button
      type="button"
      className={mergeClasses(styles.actionButton, styles.actionOrange)}
      onClick={onOpenTask}
    >
      Открыть задачу →
    </button>
  );
};

  return (
    <div className={styles.pageContainer}>
      <div className={styles.mainCard}>
        {/* Заголовок */}
        <div className={styles.titleContainer}>
          <h1 className={styles.title}>Список лабораторных работ</h1>
        </div>

        {/* Шапка таблицы */}
        <div className={styles.tableHeader}>
          <div>№ / НАЗВАНИЕ</div>
          <div>ОПИСАНИЕ</div>
          <div>СРОК СДАЧИ</div>
          <div>СТАТУС</div>
          <div>ДЕЙСТВИЕ</div>
        </div>

        {/* Прокручиваемое тело списка со скроллом */}
        <div className={styles.tableScrollBody}>
          {mockLabs.map((lab) => (
            <div key={lab.id} className={styles.row}>
              {/* Название */}
              <div>
                <div className={styles.labTitle}>{lab.title}</div>
                <div className={styles.labSubtitle}>{lab.subtitle}</div>
              </div>

              {/* Описание */}
              <div className={styles.description}>{lab.description}</div>

              {/* Срок сдачи */}
              <div>{renderDeadline(lab)}</div>

              {/* Статус */}
              <div>{renderStatus(lab.status)}</div>

              {/* Действие */}
              <div>{renderAction(lab)}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};