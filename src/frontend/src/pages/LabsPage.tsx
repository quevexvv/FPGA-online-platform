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
import { StatusBadge } from '../components/labs/StatusBadge';
import { Deadline } from '../components/labs/Deadline';
import { LabAction } from '../components/labs/LabAction';

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
});

export const LabsPage: React.FC = () => {
  const styles = useStyles();

  // Колонки таблицы: подпись и доля ширины (в сумме 100%)
  const columns = [
    { key: 'title', label: '№ / НАЗВАНИЕ', width: '27%' },
    { key: 'description', label: 'ОПИСАНИЕ', width: '27%' },
    { key: 'deadline', label: 'СРОК СДАЧИ', width: '20%' },
    { key: 'status', label: 'СТАТУС', width: '13%' },
    { key: 'action', label: 'ДЕЙСТВИЕ', width: '13%' },
  ];

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
                  <TableCell className={styles.cell}>
                    <Deadline date={lab.deadline} type={lab.deadlineType} />
                  </TableCell>
                  {/* Статус */}
                  <TableCell className={styles.cell}>
                    <StatusBadge status={lab.status} />
                  </TableCell>
                  {/* Действие */}
                  <TableCell className={styles.cell}>
                    <LabAction
                      status={lab.status}
                      isLocked={lab.isLocked}
                      labId={lab.id}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>
    </div>
  );
};