import React, { useEffect, useState } from 'react';
import {
  Button,
  makeStyles,
  mergeClasses,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableHeaderCell,
  TableRow,
  tokens,
} from '@fluentui/react-components';
import { getLabs } from '@/api/labs';
import { LabItem, LabKind, LabSummary } from '@/types';
import { StatusBadge } from '@/components/labs/StatusBadge';
import { Deadline } from '@/components/labs/Deadline';
import { LabAction } from '@/components/labs/LabAction';

// Подпись под названием: тип схемы из API
const kindLabels: Record<LabKind, string> = {
  combinational: 'Комбинационная схема',
  sequential: 'Последовательностная схема',
};

/*
  TODO: срок, статус и блокировка пока не приходят из API, 
подставляем значения по умолчанию.
  Когда бэкенд начнёт их отдавать, поменять нужно будет только эту функцию!
*/
function toLabItem(lab: LabSummary): LabItem {
  return {
    ...lab,
    subtitle: kindLabels[lab.kind],
    deadline: '—',
    deadlineType: 'future',
    status: 'not_started',
    isLocked: false,
  };
}

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
  stateMessage: {
    // Загрузка, ошибка и пустой список: сообщение по центру карточки
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    alignItems: 'center',
    gap: '12px',
    padding: '32px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
});

export const LabsPage: React.FC = () => {
  const styles = useStyles();

  // null — список ещё не пришёл
  const [labs, setLabs] = useState<LabItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Счётчик попыток: увеличиваем его, чтобы загрузить список заново
  const [reloadCount, setReloadCount] = useState(0);

  useEffect(() => {
    // Если пользователь ушёл со страницы до ответа сервера, ответ игнорируем
    let ignore = false;
    setLabs(null);
    setError(null);

    getLabs()
      .then((data) => {
        if (!ignore) setLabs(data.map(toLabItem));
      })
      .catch(() => {
        if (!ignore) setError('Не удалось загрузить список лабораторных');
      });

    return () => {
      ignore = true;
    };
  }, [reloadCount]);

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

        {error ? (
          <div className={styles.stateMessage} role="alert">
            {error}
            <Button onClick={() => setReloadCount((count) => count + 1)}>Повторить</Button>
          </div>
        ) : labs === null ? (
          <div className={styles.stateMessage}>
            <Spinner label="Загружаем лабораторные..." />
          </div>
        ) : labs.length === 0 ? (
          <div className={styles.stateMessage}>Лабораторных пока нет</div>
        ) : (
          // Таблица: заголовок и строки в одном контейнере прокрутки
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
                {labs.map((lab) => (
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
        )}
      </div>
    </div>
  );
};