import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { LabStatus } from '../../types';

const useStyles = makeStyles({
  // Кнопка без стандартного вида, чтобы выглядеть как текстовая ссылка
  button: {
    background: 'none',
    border: 'none',
    padding: 0,
    fontFamily: 'inherit',
    fontSize: '14px',
    fontWeight: '600',
    textAlign: 'left',
    cursor: 'pointer',
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
  onOpenTask: () => void;
}

export const LabAction: React.FC<LabActionProps> = ({ status, isLocked, onOpenTask }) => {
  const styles = useStyles();

  if (isLocked) {
    return <span className={styles.blocked}>Заблокировано</span>;
  }
  
  const colorClass = status === 'completed' ? styles.green : styles.orange;

  return (
    <button type="button" className={mergeClasses(styles.button, colorClass)} onClick={onOpenTask}>
      Открыть задачу&nbsp;→
    </button>
  );
};