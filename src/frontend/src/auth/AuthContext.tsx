import React, { createContext, useContext, useEffect, useState } from 'react';
import { getCurrentUser, login, logout } from '@/api/auth';
import { User } from '@/types';

interface AuthContextValue {
  user: User | null; // null — пользователь не вошёл
  isLoading: boolean; // true, пока спрашиваем сервер о сессии при запуске
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

// Контекст делает данные о входе доступными любому компоненту внутри AuthProvider
const AuthContext = createContext<AuthContextValue | null>(null);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // При запуске приложения проверяем, есть ли действующая сессия
  useEffect(() => {
    getCurrentUser()
      .then(setUser)
      .catch(() => setUser(null)) // сервер недоступен — показываем вход
      .finally(() => setIsLoading(false));
  }, []);

  const signIn = async (email: string, password: string) => {
    setUser(await login(email, password));
  };

  const signOut = async () => {
    try {
      await logout();
    } finally {
      // Даже если сессия уже истекла, на сайте пользователь должен выйти
      setUser(null);
    }
  };

  return (
    <AuthContext.Provider value={{ user, isLoading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
};

// Хук для компонентов: const { user, signOut } = useAuth();
export const useAuth = (): AuthContextValue => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth нужно использовать внутри AuthProvider');
  }
  return context;
};