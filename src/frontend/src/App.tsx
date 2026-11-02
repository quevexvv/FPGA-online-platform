import React, { useState } from 'react';
import { FluentProvider, Button, makeStyles } from '@fluentui/react-components';
import { customLightTheme, customDarkTheme } from './theme/themes';
import { AuthPage } from './pages/AuthPage';
import { WeatherMoon24Regular, WeatherSunny24Regular } from '@fluentui/react-icons';

const useStyles = makeStyles({
  themeToggle: {
    position: 'fixed',
    top: '16px',
    right: '16px',
    zIndex: 1000,
  },
});

export const App: React.FC = () => {
  const styles = useStyles();
  const [isDarkMode, setIsDarkMode] = useState(false);

  return (
    <FluentProvider theme={isDarkMode ? customDarkTheme : customLightTheme}>
      <Button
        className={styles.themeToggle}
        icon={isDarkMode ? <WeatherSunny24Regular /> : <WeatherMoon24Regular />}
        onClick={() => setIsDarkMode(!isDarkMode)}
      >
        Сменить тему
      </Button>

      <AuthPage />
    </FluentProvider>
  );
};

export default App;