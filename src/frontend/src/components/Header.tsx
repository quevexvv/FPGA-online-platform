import React from 'react';
import { Button, makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import {
  SignOut24Regular,
  WeatherMoon24Regular,
  WeatherSunny24Regular,
} from '@fluentui/react-icons';
import { useAuth } from '../auth/AuthContext';
import { NavLink } from 'react-router';

const useStyles = makeStyles({
  header: {
    height: '64px',
    // На узком экране боковые отступы уменьшаются с 32px до 16px
    padding: '0 clamp(16px, 2.5vw, 32px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: tokens.colorNeutralBackground1,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    flexShrink: 0,
  },
  // Имя и группа друг под другом
  userInfo: {
    display: 'flex',
    flexDirection: 'column',
    // Имя не сжимается и не переносится на вторую строку
    flexShrink: 0,
    whiteSpace: 'nowrap',
  },
  userText: {
    fontSize: '15px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  groupText: {
    fontSize: '12px',
    color: tokens.colorNeutralForeground2,
  },
  navContainer: {
    display: 'flex',
    // Расстояния «резиновые»: от 40px на широком экране до 16px на узком
    gap: 'clamp(16px, 2.5vw, 40px)',
    marginLeft: 'clamp(24px, 4vw, 72px)',
    // Если места не хватит даже так, вкладки прокручиваются, а не переносятся
    minWidth: 0,
    overflowX: 'auto',
    scrollbarWidth: 'thin',
    // auto забирает всё свободное место и отодвигает кнопку темы к правому краю
    marginRight: 'auto',
  },
  navLink: {
    // Ссылка без подчёркивания, выглядит как вкладка
    textDecoration: 'none',
    fontSize: '15px',
    fontWeight: '500',
    padding: '4px 0',
    whiteSpace: 'nowrap',
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
    flexShrink: 0,
    marginLeft: '16px',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: '8px',
  },
});

interface HeaderProps {
  isDarkMode: boolean;
  onThemeToggle: () => void;
}

export const Header: React.FC<HeaderProps> = ({ isDarkMode, onThemeToggle }) => {
  const styles = useStyles();
  const { user, signOut } = useAuth();

  // Вкладки шапки: адрес страницы и подпись
  const navItems = [
    { to: '/labs', label: 'Лабораторные' },
    { to: '/workspace', label: 'Рабочее пространство' },
    { to: '/booking', label: 'Бронь' },
    { to: '/history', label: 'История' },
  ];

  return (
    <header className={styles.header}>
      <div className={styles.userInfo}>
        <span className={styles.userText}>{user?.full_name}</span>
        {/* Группы может не быть: у преподавателя или если студент её не указал */}
        {user?.group && <span className={styles.groupText}>{user.group}</span>}
      </div>
      
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

      {/* Кнопки темы и выхода в правом углу */}
      <div className={styles.rightSection}>
        <Button
          appearance="subtle"
          icon={isDarkMode ? <WeatherSunny24Regular /> : <WeatherMoon24Regular />}
          onClick={onThemeToggle}
          aria-label="Сменить тему"
        />
        <Button
          appearance="subtle"
          icon={<SignOut24Regular />}
          onClick={signOut}
          aria-label="Выйти"
          title="Выйти"
        />
      </div>
    </header>
  );
};