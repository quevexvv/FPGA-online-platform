import React, { useState } from 'react';
import { FluentProvider, makeStyles, tokens } from '@fluentui/react-components';
import { customLightTheme, customDarkTheme } from './theme/themes';
import { AuthPage } from './pages/AuthPage';
import { Header } from './components/Header';
import { LabsPage } from './pages/LabsPage';
import { WorkspacePage } from './pages/WorkspacePage';
import { BookingPage } from './pages/BookingPage';
import { HistoryPage } from './pages/HistoryPage';
import { LabTaskPage } from './pages/LabTaskPage';
import { PageType, TabType } from './types';

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
  const [currentPage, setCurrentPage] = useState<PageType>('labs');

// Страницы задания и кода открываются из лабораторных, поэтому в шапке активна эта вкладка
  const currentTab: TabType = currentPage === 'lab-task' ? 'labs' : currentPage;

  return (
    <FluentProvider theme={isDarkMode ? customDarkTheme : customLightTheme}>
      {!isLoggedIn ? (
        <AuthPage onLogin={() => setIsLoggedIn(true)} />
      ) : (
        <div className={styles.appContainer}>
          {/* Хэдер со всеми вкладками и кнопкой смены темы */}
          <Header
            currentTab={currentTab}
            onTabChange={setCurrentPage}
            isDarkMode={isDarkMode}
            onThemeToggle={() => setIsDarkMode(!isDarkMode)}
          />

          {/* Тело страниц */}
          <main style={{ flex: 1, overflow: 'hidden' }}>
            {currentPage === 'labs' && <LabsPage onOpenTask={() => setCurrentPage('lab-task')} />}
            {currentPage === 'workspace' && <WorkspacePage />}
            {currentPage === 'booking' && <BookingPage />}
            {currentPage === 'history' && <HistoryPage />}
            {currentPage === 'lab-task' && <LabTaskPage />}
          </main>
        </div>
      )}
    </FluentProvider>
  );
};

export default App;