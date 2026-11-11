import React from 'react';
import { Button, makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { WeatherMoon24Regular, WeatherSunny24Regular } from '@fluentui/react-icons';
import { NavLink } from 'react-router';

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
    marginLeft: '72px',
    // auto забирает всё свободное место и отодвигает кнопку темы к правому краю
    marginRight: 'auto',
  },
  navLink: {
    // Ссылка без подчёркивания, выглядит как вкладка
    textDecoration: 'none',
    fontSize: '15px',
    fontWeight: '500',
    padding: '4px 0',
    transition: 'color 0.2s',
  },
  navLinkActive: {
    fontWeight: '700',
    color: tokens.colorBrandForeground1,
  },
  navLinkInactive: {
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
  isDarkMode: boolean;
  onThemeToggle: () => void;
}

export const Header: React.FC<HeaderProps> = ({ isDarkMode, onThemeToggle }) => {
  const styles = useStyles();

  // Вкладки шапки: адрес страницы и подпись
  const navItems = [
    { to: '/labs', label: 'Лабораторные' },
    { to: '/workspace', label: 'Рабочее пространство' },
    { to: '/booking', label: 'Бронь' },
    { to: '/history', label: 'История' },
  ];

  return (
    <header className={styles.header}>
      <div className={styles.userText}>Иванов Иван (8К51Т)</div>
      
      {/* Навигация сразу после имени */}
      <nav className={styles.navContainer}>
        {navItems.map((item) => (
          // NavLink сам знает, открыта ли его страница, и передаёт это в isActive
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) =>
              mergeClasses(styles.navLink, isActive ? styles.navLinkActive : styles.navLinkInactive)
            }
          >
            {item.label}
          </NavLink>
        ))}
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