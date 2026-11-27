import React, { useEffect, useState } from 'react';
import {
  Button,
  Card,
  CardHeader,
  Field,
  Input,
  Text,
  Title2,
  Title3,
} from '@fluentui/react-components';
import { Link } from 'react-router';
import { useAuthStyles } from './authStyles';
import { ThemeToggle, type ThemeToggleProps } from '@/components/ThemeToggle';

const REGISTRATION_DRAFT_KEY = 'fpga:registration-draft';

interface RegistrationDraft {
  firstName: string;
  lastName: string;
  email: string;
  group: string;
}

const emptyDraft: RegistrationDraft = {
  firstName: '',
  lastName: '',
  email: '',
  group: '',
};

function readRegistrationDraft(): RegistrationDraft {
  try {
    const raw = sessionStorage.getItem(REGISTRATION_DRAFT_KEY);

    if (!raw) return emptyDraft;

    const saved = JSON.parse(raw) as Partial<RegistrationDraft> | null;

    return {
      firstName: typeof saved?.firstName === 'string' ? saved.firstName : '',
      lastName: typeof saved?.lastName === 'string' ? saved.lastName : '',
      email: typeof saved?.email === 'string' ? saved.email : '',
      group: typeof saved?.group === 'string' ? saved.group : '',
    };
  } catch {
    return emptyDraft;
  }
}

export const RegistrationPage: React.FC<ThemeToggleProps> = ({ isDarkMode, onThemeToggle }) => {
  const styles = useAuthStyles();

  const [draft, setDraft] = useState(readRegistrationDraft);
  const { firstName, lastName, email, group } = draft;

  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  function updateDraft(field: keyof RegistrationDraft, value: string) {
    setDraft((current) => ({
      ...current,
      [field]: value,
    }));
  }

  // Сохраняем только данные регистрации, без паролей
  useEffect(() => {
    try {
      const isEmpty = Object.values(draft).every((value) => value === '');

      if (isEmpty) {
        sessionStorage.removeItem(REGISTRATION_DRAFT_KEY);
      } else {
        sessionStorage.setItem(REGISTRATION_DRAFT_KEY, JSON.stringify(draft));
      }
    } catch {
      // Если хранилище недоступно, форма продолжает работать
    }
  }, [draft]);

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

        <Title3 as="h1" block align="center">
          Регистрация
        </Title3>

        <form className={styles.form} onSubmit={(event) => event.preventDefault()}>
          <Field label="Имя" required>
            <Input
              autoComplete="given-name"
              value={firstName}
              onChange={(_, data) => updateDraft('firstName', data.value)}
            />
          </Field>

          <Field label="Фамилия" required>
            <Input
              autoComplete="family-name"
              value={lastName}
              onChange={(_, data) => updateDraft('lastName', data.value)}
            />
          </Field>

          <Field label="Email" required>
            <Input
              type="email"
              autoComplete="email"
              value={email}
              onChange={(_, data) => updateDraft('email', data.value)}
            />
          </Field>

          <Field label="Учебная группа" hint="Необязательное поле">
            <Input
              placeholder="8К51Т"
              value={group}
              onChange={(_, data) => updateDraft('group', data.value)}
            />
          </Field>

          <Field label="Пароль" hint="От 12 символов" required>
            <Input
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(_, data) => setPassword(data.value)}
            />
          </Field>

          <Field label="Повтор пароля" required>
            <Input
              type="password"
              autoComplete="new-password"
              value={confirmPassword}
              onChange={(_, data) => setConfirmPassword(data.value)}
            />
          </Field>

          <Button type="submit" appearance="primary" size="large" disabled>
            Зарегистрироваться
          </Button>
        </form>

        <Text as="p" className={styles.footer}>
          Уже есть аккаунт?{' '}
          <Link to="/login" className={styles.link}>
            Войти
          </Link>
        </Text>
      </Card>
    </main>
  );
};
