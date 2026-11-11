import React, { useState } from 'react';
import { FluentProvider, makeStyles, tokens } from '@fluentui/react-components';
import { Navigate, Route, Routes } from 'react-router';
import { customLightTheme, customDarkTheme } from './theme/themes';
import { AuthPage } from './pages/AuthPage';
import { Header } from './components/Header';
import { LabsPage } from './pages/LabsPage';
import { WorkspacePage } from './pages/WorkspacePage';
import { BookingPage } from './pages/BookingPage';
import { HistoryPage } from './pages/HistoryPage';
import { LabTaskPage } from './pages/LabTaskPage';

const useStyles = makeStyles({
  appContainer: {
    width: '100vw',
    height: '100vh',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    backgroundColor: tokens.colorNeutralBackground2,
  },
});

export const App: React.FC = () => {
  const styles = useStyles();
  const [isDarkMode, setIsDarkMode] = useState(false);
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  

  return (
    <FluentProvider theme={isDarkMode ? customDarkTheme : customLightTheme}>
      {!isLoggedIn ? (
        <AuthPage onLogin={() => setIsLoggedIn(true)} />
      ) : (
        <div className={styles.appContainer}>
          {/* Хэдер со всеми вкладками и кнопкой смены темы */}
          <Header
            isDarkMode={isDarkMode}
            onThemeToggle={() => setIsDarkMode(!isDarkMode)}
          />

          {/* Тело страниц */}
          <main style={{ flex: 1, overflow: 'hidden' }}>
            {/* Какую страницу показать, решает адрес в браузере */}
            <Routes>
              <Route path="/" element={<Navigate to="/labs" replace />} />
              <Route path="/labs" element={<LabsPage />} />
              <Route path="/labs/:labId" element={<LabTaskPage />} />
              <Route path="/workspace" element={<WorkspacePage />} />
              <Route path="/booking" element={<BookingPage />} />
              <Route path="/history" element={<HistoryPage />} />
              {/* Любой неизвестный адрес ведёт к списку лабораторных */}
              <Route path="*" element={<Navigate to="/labs" replace />} />
            </Routes>
          </main>
        </div>
      )}
    </FluentProvider>
  );
};

export default App;