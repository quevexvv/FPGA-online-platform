import React from 'react';
import { makeStyles, tokens } from '@fluentui/react-components';
import { LabItem } from '@/types';

const useStyles = makeStyles({
  // Срок сдачи: выделяем только сегодняшний и уже сданный
  today: {
    fontWeight: '600',
    color: tokens.colorStatusWarningForeground1,
  },
  completed: {
    fontWeight: '600',
    color: tokens.colorStatusSuccessForeground1,
  },
});

interface DeadlineProps {
  date: string;
  type: LabItem['deadlineType'];
}

export const Deadline: React.FC<DeadlineProps> = ({ date, type }) => {
  const styles = useStyles();

  if (type === 'today') {
    return <span className={styles.today}>{date}</span>;
  }
  if (type === 'completed') {
    return <span className={styles.completed}>{date}</span>;
  }
  return <span>{date}</span>;
};