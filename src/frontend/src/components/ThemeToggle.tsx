import React from 'react';
import { Button } from '@fluentui/react-components';
import { WeatherMoon24Regular, WeatherSunny24Regular } from '@fluentui/react-icons';

export interface ThemeToggleProps {
  isDarkMode: boolean;
  onThemeToggle: () => void;
}

export const ThemeToggle: React.FC<ThemeToggleProps> = ({ isDarkMode, onThemeToggle }) => {
  const label = isDarkMode ? 'Включить светлую тему' : 'Включить тёмную тему';

  return (
    <Button
      type="button"
      appearance="subtle"
      icon={isDarkMode ? <WeatherSunny24Regular /> : <WeatherMoon24Regular />}
      onClick={onThemeToggle}
      aria-label={label}
      title={label}
    />
  );
};
