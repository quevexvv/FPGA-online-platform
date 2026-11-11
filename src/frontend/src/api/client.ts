// Все запросы к бэкенду идут через /api: dev-сервер Vite пересылает их на бэкенд
const API_BASE = '/api';
const CSRF_STORAGE_KEY = 'csrf_token';

// Ошибка ответа сервера. Храним код ответа, чтобы отличать, например, 401 от 422
export class ApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

// CSRF-токен нужен для запросов, которые меняют данные (выход, отправка кода).
// Храним его до закрытия вкладки
export const csrfStorage = {
  get: () => sessionStorage.getItem(CSRF_STORAGE_KEY),
  set: (token: string) => sessionStorage.setItem(CSRF_STORAGE_KEY, token),
  clear: () => sessionStorage.removeItem(CSRF_STORAGE_KEY),
};

interface RequestOptions {
  method?: 'GET' | 'POST';
  body?: unknown;
  withCsrf?: boolean;
}

// Достаём из ответа понятное сообщение об ошибке, если сервер его прислал
async function readErrorMessage(response: Response): Promise<string> {
  try {
    const data = await response.json();
    if (typeof data.detail === 'string') {
      return data.detail;
    }
  } catch {
    // Тело ответа не JSON — используем стандартный текст ниже
  }
  return `Ошибка сервера: ${response.status}`;
}

// Один общий способ обращаться к API: адрес, cookie, JSON и обработка ошибок
export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body, withCsrf = false } = options;

  const headers: Record<string, string> = {};
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  if (withCsrf) {
    const token = csrfStorage.get();
    if (token) {
      headers['X-CSRF-Token'] = token;
    }
  }

  const response = await fetch(`${API_BASE}${path}`, {
    method,
    headers,
    credentials: 'include', // отправлять cookie сессии
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  if (!response.ok) {
    throw new ApiError(response.status, await readErrorMessage(response));
  }

  // 204 No Content: сервер ничего не вернул
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}