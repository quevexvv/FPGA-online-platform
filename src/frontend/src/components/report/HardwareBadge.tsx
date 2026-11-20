import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { DeveloperBoard16Regular } from '@fluentui/react-icons';
import { RunStatus } from '@/types';

const useStyles = makeStyles({
  badge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '4px',
    flexShrink: 0,
    whiteSpace: 'nowrap',
    padding: '3px 10px',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: '700',
  },
  hardware: {
    backgroundColor: tokens.colorStatusSuccessBackground1,
    color: tokens.colorStatusSuccessForeground1,
  },
  mock: {
    backgroundColor: tokens.colorNeutralBackground3,
    color: tokens.colorNeutralForeground2,
  },
});

// Бейдж «Проверено на плате» или «Без платы» для демонстрационной проверки
export const HardwareBadge: React.FC<{ run: RunStatus | null }> = ({ run }) => {
  const styles = useStyles();

  if (run?.mode === 'mock') {
    return (
      <span className={mergeClasses(styles.badge, styles.mock)}>Без платы, не засчитывается</span>
    );
  }
  if (!run?.hardware_verified) return null;
  return (
    <span className={mergeClasses(styles.badge, styles.hardware)}>
      <DeveloperBoard16Regular aria-hidden />
      Проверено на плате
    </span>
  );
};
