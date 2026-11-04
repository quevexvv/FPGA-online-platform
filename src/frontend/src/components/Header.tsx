import React from 'react';
import { Button, makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { WeatherMoon24Regular, WeatherSunny24Regular } from '@fluentui/react-icons';
import { TabType } from '../types';

const useStyles = makeStyles({
  header: {
    height: '64px',
    padding: '0 32px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: tokens.colorNeutralBackground1,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    flexShrink: 0,
  },
  userText: {
    fontSize: '15px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  navContainer: {
    display: 'flex',
    gap: '40px',

    marginLeft: '24px',
  },
  navButton: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    fontFamily: 'inherit',
    fontSize: '15px',
    fontWeight: '500',
    padding: '4px 0',
    transition: 'color 0.2s',
  },
  navButtonActive: {
    fontWeight: '700',
    color: tokens.colorBrandBackground,
  },
  navButtonInactive: {
    color: tokens.colorNeutralForeground2,
    ':hover': {
      color: tokens.colorNeutralForeground1,
    },
  },
  rightSection: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'flex-end',
    minWidth: '60px',
  },
});

interface HeaderProps {
  currentTab: TabType;
  onTabChange: (tab: TabType) => void;
  isDarkMode: boolean;
  onThemeToggle: () => void;
}

export const Header: React.FC<HeaderProps> = ({
  currentTab,
  onTabChange,
  isDarkMode,
  onThemeToggle,
}) => {
  const styles = useStyles();

  const navItems: { id: TabType; label: string }[] = [
    { id: 'labs', label: 'Лабораторные' },
    { id: 'workspace', label: 'Рабочее пространство' },
    { id: 'booking', label: 'Бронь' },
    { id: 'history', label: 'История' },
  ];

  return (
    <header className={styles.header}>
      <div className={styles.userText}>Иванов Иван (8К51Т)</div>

      <nav className={styles.navContainer}>
        {navItems.map((item) => {
          const isActive = currentTab === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onTabChange(item.id)}
              className={mergeClasses(styles.navButton,
    isActive ? styles.navButtonActive : styles.navButtonInactive
)}
            >
              {item.label}
            </button>
          );
        })}
      </nav>

      {/* Кнопка смены темы в самом правому углу */}
      <div className={styles.rightSection}>
        <Button
          appearance="subtle"
          icon={isDarkMode ? <WeatherSunny24Regular /> : <WeatherMoon24Regular />}
          onClick={onThemeToggle}
          aria-label="Сменить тему"
        />
      </div>
    </header>
  );
};