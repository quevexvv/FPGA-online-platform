interface RegistrationValues {
  firstName: string;
  lastName: string;
  email: string;
  group: string;
  password: string;
  confirmPassword: string;
}

export type RegistrationErrors = Partial<Record<keyof RegistrationValues, string>>;

// Считаем символы Unicode, как на бэкенде
function textLength(value: string): number {
  return Array.from(value).length;
}

export function validateRegistration(values: RegistrationValues): RegistrationErrors {
  const errors: RegistrationErrors = {};

  const firstName = values.firstName.trim();
  const lastName = values.lastName.trim();
  const email = values.email.trim();
  const group = values.group.trim();

  if (!firstName) {
    errors.firstName = 'Введите имя';
  } else if (textLength(firstName) > 30) {
    errors.firstName = 'Имя не должно превышать 30 символов';
  }

  if (!lastName) {
    errors.lastName = 'Введите фамилию';
  } else if (textLength(lastName) > 50) {
    errors.lastName = 'Фамилия не должна превышать 50 символов';
  }

  if (!email) {
    errors.email = 'Введите email';
  } else if (textLength(email) > 254) {
    errors.email = 'Email не должен превышать 254 символа';
  } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    errors.email = 'Введите корректный email';
  }

  if (textLength(group) > 32) {
    errors.group = 'Группа не должна превышать 32 символа';
  } else if (Array.from(group).some((char) => char !== ' ' && /[\p{C}\p{Z}]/u.test(char))) {
    errors.group = 'Группа содержит недопустимые символы';
  }

  if (!values.password) {
    errors.password = 'Введите пароль';
  } else if (textLength(values.password) < 12) {
    errors.password = 'Пароль должен содержать не менее 12 символов';
  } else if (textLength(values.password) > 128) {
    errors.password = 'Пароль не должен превышать 128 символов';
  }

  if (!values.confirmPassword) {
    errors.confirmPassword = 'Повторите пароль';
  } else if (values.password !== values.confirmPassword) {
    errors.confirmPassword = 'Пароли не совпадают';
  }

  return errors;
}
