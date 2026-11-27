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
import { Link, useNavigate } from 'react-router';
import { register } from '@/api/auth';
import { ApiError } from '@/api/client';
import { useAuthStyles } from './authStyles';
import { ThemeToggle, type ThemeToggleProps } from '@/components/ThemeToggle';
import { validateRegistration, type RegistrationErrors } from './registrationValidation';

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
  const navigate = useNavigate();

  const [draft, setDraft] = useState(readRegistrationDraft);
  const { firstName, lastName, email, group } = draft;

  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  // Показываем ошибки только после первой попытки отправки
  const [hasSubmitted, setHasSubmitted] = useState(false);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);

  const errors = validateRegistration({
    ...draft,
    password,
    confirmPassword,
  });

  const visibleErrors: RegistrationErrors = hasSubmitted
    ? errors
    : {
        firstName: firstName.trim() ? errors.firstName : undefined,
        lastName: lastName.trim() ? errors.lastName : undefined,
      };
  const isValid = Object.keys(errors).length === 0;

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

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (isSubmitting) return;

    setHasSubmitted(true);
    setServerError(null);

    if (!isValid) return;

    setIsSubmitting(true);

    try {
      const registeredUser = await register({
        email: email.trim().toLowerCase(),
        full_name: `${lastName.trim()} ${firstName.trim()}`,
        group: group.trim() || null,
        password,
      });

      // После успешной регистрации черновик больше не нужен
      try {
        sessionStorage.removeItem(REGISTRATION_DRAFT_KEY);
      } catch {
        // Недоступность хранилища не отменяет регистрацию
      }

      // Переходим на вход и передаём email созданного аккаунта
      navigate('/login', {
        replace: true,
        state: {
          registeredEmail: registeredUser.email,
        },
      });
    } catch (error) {
      if (error instanceof ApiError) {
        switch (error.status) {
          case 409:
            setServerError('Пользователь с таким email уже существует');
            break;

          case 422:
            setServerError('Проверьте правильность заполнения полей');
            break;

          case 403:
            setServerError('Сервер отклонил запрос на регистрацию');
            break;

          default:
            setServerError('Не удалось создать аккаунт. Попробуйте позже');
        }
      } else {
        setServerError('Не удалось связаться с сервером. Попробуйте ещё раз');
      }
    } finally {
      setIsSubmitting(false);
    }
  }

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

        <form className={styles.form} onSubmit={handleSubmit} noValidate>
          <Field
            label="Имя"
            required
            validationState={visibleErrors.firstName ? 'error' : 'none'}
            validationMessage={visibleErrors.firstName}
          >
            <Input
              autoComplete="given-name"
              value={firstName}
              disabled={isSubmitting}
              onChange={(_, data) => updateDraft('firstName', data.value)}
            />
          </Field>

          <Field
            label="Фамилия"
            required
            validationState={visibleErrors.lastName ? 'error' : 'none'}
            validationMessage={visibleErrors.lastName}
          >
            <Input
              autoComplete="family-name"
              value={lastName}
              disabled={isSubmitting}
              onChange={(_, data) => updateDraft('lastName', data.value)}
            />
          </Field>

          <Field
            label="Email"
            required
            validationState={visibleErrors.email ? 'error' : 'none'}
            validationMessage={visibleErrors.email}
          >
            <Input
              type="email"
              autoComplete="email"
              value={email}
              disabled={isSubmitting}
              onChange={(_, data) => updateDraft('email', data.value)}
            />
          </Field>

          <Field
            label="Учебная группа"
            hint="Необязательное поле"
            validationState={visibleErrors.group ? 'error' : 'none'}
            validationMessage={visibleErrors.group}
          >
            <Input
              placeholder="8К51Т"
              value={group}
              disabled={isSubmitting}
              onChange={(_, data) => updateDraft('group', data.value)}
            />
          </Field>

          <Field
            label="Пароль"
            hint="От 12 до 128 символов"
            required
            validationState={visibleErrors.password ? 'error' : 'none'}
            validationMessage={visibleErrors.password}
          >
            <Input
              type="password"
              autoComplete="new-password"
              value={password}
              disabled={isSubmitting}
              onChange={(_, data) => setPassword(data.value)}
            />
          </Field>

          <Field
            label="Повтор пароля"
            required
            validationState={visibleErrors.confirmPassword ? 'error' : 'none'}
            validationMessage={visibleErrors.confirmPassword}
          >
            <Input
              type="password"
              autoComplete="new-password"
              value={confirmPassword}
              disabled={isSubmitting}
              onChange={(_, data) => setConfirmPassword(data.value)}
            />
          </Field>

          {serverError && (
            <Text role="alert" className={styles.error}>
              {serverError}
            </Text>
          )}

          <Button type="submit" appearance="primary" size="large" disabled={isSubmitting}>
            {isSubmitting ? 'Регистрация...' : 'Зарегистрироваться'}
          </Button>
        </form>

        <Text as="p" className={styles.footer}>
          Уже есть аккаунт?{' '}
          {isSubmitting ? (
            <Text>Войти</Text>
          ) : (
            <Link to="/login" className={styles.link}>
              Войти
            </Link>
          )}
        </Text>
      </Card>
    </main>
  );
};
