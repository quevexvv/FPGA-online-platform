import React, { lazy, Suspense, useState } from 'react';
import { FluentProvider, makeStyles, Spinner, tokens } from '@fluentui/react-components';
import { Navigate, Route, Routes } from 'react-router';
import { customLightTheme, customDarkTheme } from '@/theme/themes';
import { AuthPage } from '@/pages/AuthPage';
import { Header } from '@/components/Header';
import { LabsPage } from '@/pages/LabsPage';
import { BookingPage } from '@/pages/BookingPage';
import { HistoryPage } from '@/pages/HistoryPage';
import { LabTaskPage } from '@/pages/LabTaskPage';
import { useAuth } from '@/auth/AuthContext';

// Рабочее пространство с редактором кода — самая тяжёлая страница (CodeMirror).
// Загружаем её отдельным файлом, только когда студент её открывает
const WorkspacePage = lazy(() =>
  import('@/pages/WorkspacePage').then((module) => ({ default: module.WorkspacePage })),
);

const useStyles = makeStyles({
  appContainer: {
    width: '100vw',
    height: '100vh',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  pageSpinner: {
    height: '100%',
  },
  loadingScreen: {
    width: '100vw',
    height: '100vh',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: tokens.colorNeutralBackground2,
  },
});

export const App: React.FC = () => {
  const styles = useStyles();
  const [isDarkMode, setIsDarkMode] = useState(false);
  const { user, isLoading } = useAuth();

  return (
    <FluentProvider theme={isDarkMode ? customDarkTheme : customLightTheme}>
      {isLoading ? (
        // Пока сервер отвечает, вошёл ли пользователь, показываем индикатор загрузки
        <div className={styles.loadingScreen}>
          <Spinner label="Загрузка..." />
        </div>
      ) : !user ? (
        <AuthPage />
      ) : (
        <div className={styles.appContainer}>
          {/* Хэдер со всеми вкладками и кнопкой смены темы */}
          <Header isDarkMode={isDarkMode} onThemeToggle={() => setIsDarkMode(!isDarkMode)} />

          {/* Тело страниц */}
          <main style={{ flex: 1, overflow: 'hidden' }}>
            {/* Какую страницу показать, решает адрес в браузере.
                Пока загружается файл страницы, Suspense показывает индикатор */}
            <Suspense fallback={<Spinner className={styles.pageSpinner} label="Загрузка..." />}>
              <Routes>
                <Route path="/" element={<Navigate to="/labs" replace />} />
                <Route path="/labs" element={<LabsPage />} />
                <Route path="/labs/:labId" element={<LabTaskPage />} />
                <Route path="/workspace" element={<WorkspacePage />} />
                <Route path="/workspace/:labId" element={<WorkspacePage />} />
                <Route path="/booking" element={<BookingPage />} />
                <Route path="/history" element={<HistoryPage />} />
                {/* Любой неизвестный адрес ведёт к списку лабораторных */}
                <Route path="*" element={<Navigate to="/labs" replace />} />
              </Routes>
            </Suspense>
          </main>
        </div>
      )}
    </FluentProvider>
  );
};

export default App;
