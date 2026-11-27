import React, { useState } from 'react';
import { Button, Card, CardHeader, Field, Input, Text, Title2 } from '@fluentui/react-components';
import { Link } from 'react-router';
import { useAuth } from '@/auth/AuthContext';
import { ApiError } from '@/api/client';
import { useAuthStyles } from './authStyles';
import { ThemeToggle, type ThemeToggleProps } from '@/components/ThemeToggle';

export const AuthPage: React.FC<ThemeToggleProps> = ({ isDarkMode, onThemeToggle }) => {
  const styles = useAuthStyles();
  const { signIn } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (event: React.FormEvent) => {
    // Без этого браузер перезагрузил бы страницу при отправке формы
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await signIn(email.trim(), password);
    } catch (err) {
      setError(
        err instanceof ApiError && err.status === 401
          ? 'Неверный email или пароль'
          : 'Не удалось войти. Проверьте, что сервер запущен',
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <main className={styles.pageLayout}>
      <div className={styles.themeToolbar}>
        <ThemeToggle isDarkMode={isDarkMode} onThemeToggle={onThemeToggle} />
      </div>

      <Card className={styles.card}>
        <CardHeader
          header={
            <Title2 block align="center">
              FPGA Remote Lab
            </Title2>
          }
        />

        <form className={styles.form} onSubmit={handleSubmit}>
          <Field label="Email" required>
            <Input
              type="email"
              autoComplete="username"
              value={email}
              onChange={(_, data) => setEmail(data.value)}
            />
          </Field>

          <Field label="Пароль" required>
            <Input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(_, data) => setPassword(data.value)}
            />
          </Field>

          {error && (
            <Text role="alert" className={styles.error}>
              {error}
            </Text>
          )}

          <Button type="submit" appearance="primary" size="large" disabled={isSubmitting}>
            {isSubmitting ? 'Входим...' : 'Войти'}
          </Button>
        </form>

        <Text as="p" className={styles.footer}>
          Нет аккаунта?{' '}
          <Link to="/register" className={styles.link}>
            Зарегистрироваться
          </Link>
        </Text>
      </Card>
    </main>
  );
};
