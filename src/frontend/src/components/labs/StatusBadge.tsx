import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { LabStatus } from '../../types';

const useStyles = makeStyles({
  // Общая форма бейджа, цвета задаются отдельными стилями ниже
  badge: {
    display: 'inline-flex',
    alignItems: 'center',
    whiteSpace: 'nowrap',
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
  },
  completed: {
    backgroundColor: tokens.colorStatusSuccessBackground1,
    color: tokens.colorStatusSuccessForeground1,
  },
  in_progress: {
    backgroundColor: tokens.colorStatusWarningBackground1,
    color: tokens.colorStatusWarningForeground1,
  },
  not_started: {
    backgroundColor: tokens.colorNeutralBackground3,
    color: tokens.colorNeutralForeground3,
  },
});

// Подпись для каждого статуса
const labels: Record<LabStatus, string> = {
  completed: 'Выполнено',
  in_progress: 'В работе',
  not_started: 'Не начато',
};

interface StatusBadgeProps {
  status: LabStatus;
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({ status }) => {
  const styles = useStyles();

  return <span className={mergeClasses(styles.badge, styles[status])}>{labels[status]}</span>;
};