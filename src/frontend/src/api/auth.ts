import { User } from '@/types';
import { ApiError, apiRequest, csrfStorage } from './client';

interface LoginResult {
  user: User;
  csrf_token: string;
}

// Вход: сервер ставит cookie сессии, а CSRF-токен присылает в ответе
export async function login(email: string, password: string): Promise<User> {
  const result = await apiRequest<LoginResult>('/auth/login', {
    method: 'POST',
    body: { email, password },
  });
  csrfStorage.set(result.csrf_token);
  return result.user;
}

// Текущий пользователь по cookie сессии. null — если не вошёл или сессия истекла
export async function getCurrentUser(): Promise<User | null> {
  try {
    return await apiRequest<User>('/auth/me');
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      return null;
    }
    throw error;
  }
}

// Выход. CSRF-токен apiRequest подставит сам, даже в новой вкладке
export async function logout(): Promise<void> {
  try {
    await apiRequest<void>('/auth/logout', { method: 'POST', withCsrf: true });
  } finally {
    csrfStorage.clear();
  }
}
