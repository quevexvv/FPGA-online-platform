import React from 'react';
import {
  makeStyles,
  mergeClasses,
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableHeaderCell,
  TableRow,
  tokens,
} from '@fluentui/react-components';
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
  // Прокручивается вся таблица вместе с заголовком, поэтому колонки всегда совпадают
  tableScroll: {
    flex: 1,
    overflowY: 'auto',
    padding: '0 32px',
    scrollbarWidth: 'thin',
    scrollbarColor: `${tokens.colorNeutralStroke1} transparent`,
  },
  table: {
    // Уже этой ширины таблица не сжимается, а прокручивается по горизонтали
    minWidth: '880px',
  },
  headerRow: {
    // Линию под заголовком рисует headerCell, потому что граница строки уезжает при прокрутке
    borderBottom: 'none',
  },
  headerCell: {
    // Заголовок остаётся на месте, пока список прокручивается под ним
    position: 'sticky',
    top: 0,
    zIndex: 1,
    height: 'auto',
    padding: '12px 16px 12px 0',
    backgroundColor: tokens.colorNeutralBackground1,
    boxShadow: `inset 0 -1px 0 ${tokens.colorNeutralStroke1}`,
    fontSize: '12px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground2,
    letterSpacing: '0.5px',
  },
  row: {
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
  cell: {
    height: 'auto',
    padding: '20px 16px 20px 0',
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
    backgroundColor: tokens.colorStatusSuccessBackground1,
    color: tokens.colorStatusSuccessForeground1,
    width: 'fit-content',
  },
  badgeInProgress: {
    display: 'inline-flex',
    alignItems: 'center',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
    backgroundColor: tokens.colorStatusWarningBackground1,
    color: tokens.colorStatusWarningForeground1,
    width: 'fit-content',
  },
  badgeNotStarted: {
    display: 'inline-flex',
    alignItems: 'center',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
    backgroundColor: tokens.colorNeutralBackground3,
    color: tokens.colorNeutralForeground3,
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
    color: tokens.colorBrandForeground1,
  },
  actionOrange: {
    color: tokens.colorStatusWarningForeground1,
  },
  actionBlocked: {
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorNeutralForegroundDisabled,
  },
  // Срок сдачи: выделяем только сегодняшний и уже сданный
  deadlineToday: {
    fontWeight: '600',
    color: tokens.colorStatusWarningForeground1,
  },
  deadlineCompleted: {
    fontWeight: '600',
    color: tokens.colorStatusSuccessForeground1,
  },
});

interface LabsPageProps {
  onOpenTask: () => void;
  onOpenCode: () => void;
}

export const LabsPage: React.FC<LabsPageProps> = ({ onOpenTask, onOpenCode }) => {
  const styles = useStyles();

  // Колонки таблицы: подпись и доля ширины (в сумме 100%)
  const columns = [
    { key: 'title', label: '№ / НАЗВАНИЕ', width: '27%' },
    { key: 'description', label: 'ОПИСАНИЕ', width: '27%' },
    { key: 'deadline', label: 'СРОК СДАЧИ', width: '20%' },
    { key: 'status', label: 'СТАТУС', width: '13%' },
    { key: 'action', label: 'ДЕЙСТВИЕ', width: '13%' },
  ];

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
      return <span className={styles.deadlineToday}>{lab.deadline}</span>;
    }
    if (lab.deadlineType === 'completed') {
      return <span className={styles.deadlineCompleted}>{lab.deadline}</span>;
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

        {/* Таблица: заголовок и строки в одном контейнере прокрутки */}
        <div className={styles.tableScroll}>
          <Table aria-label="Список лабораторных работ" className={styles.table}>
            <TableHeader>
              <TableRow className={styles.headerRow}>
                {columns.map((column) => (
                  <TableHeaderCell
                    key={column.key}
                    className={styles.headerCell}
                    style={{ width: column.width }}
                  >
                    {column.label}
                  </TableHeaderCell>
                ))}
              </TableRow>
            </TableHeader>

            <TableBody>
              {mockLabs.map((lab) => (
                <TableRow key={lab.id} className={styles.row}>
                  {/* Название */}
                  <TableCell className={styles.cell}>
                    <div className={styles.labTitle}>{lab.title}</div>
                    <div className={styles.labSubtitle}>{lab.subtitle}</div>
                  </TableCell>

                  {/* Описание */}
                  <TableCell className={mergeClasses(styles.cell, styles.description)}>
                    {lab.description}
                  </TableCell>

                  {/* Срок сдачи */}
                  <TableCell className={styles.cell}>{renderDeadline(lab)}</TableCell>

                  {/* Статус */}
                  <TableCell className={styles.cell}>{renderStatus(lab.status)}</TableCell>

                  {/* Действие */}
                  <TableCell className={styles.cell}>{renderAction(lab)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>
    </div>
  );
};