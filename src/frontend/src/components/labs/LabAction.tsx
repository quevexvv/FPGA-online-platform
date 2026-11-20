import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { Link } from 'react-router';
import { LabStatus } from '@/types';

const useStyles = makeStyles({
  // Ссылка без подчёркивания
  link: {
    textDecoration: 'none',
    fontSize: '14px',
    fontWeight: '600',
  },
  green: {
    color: tokens.colorBrandForeground1,
  },
  orange: {
    color: tokens.colorStatusWarningForeground1,
  },
  blocked: {
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorNeutralForegroundDisabled,
  },
});

interface LabActionProps {
  status: LabStatus;
  isLocked: boolean;
  labId: string;
}

export const LabAction: React.FC<LabActionProps> = ({ status, isLocked, labId }) => {
  const styles = useStyles();

  if (isLocked) {
    return <span className={styles.blocked}>Заблокировано</span>;
  }

  const colorClass = status === 'completed' ? styles.green : styles.orange;

  return (
    <Link to={`/labs/${labId}`} className={mergeClasses(styles.link, colorClass)}>
      Открыть задачу&nbsp;→
    </Link>
  );
};
