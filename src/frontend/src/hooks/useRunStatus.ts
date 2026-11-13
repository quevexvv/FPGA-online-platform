import { useEffect, useState } from 'react';
import { ApiError } from '@/api/client';
import { getSubmissionRun } from '@/api/submissions';
import { RunStatus } from '@/types';

// Через сколько повторить запрос, если сервер не ответил
const RETRY_DELAY_MS = 5000;

// Следит за проверкой отправленного решения: спрашивает сервер, пока проверка идёт.
// submissionId = null — следить не за чем (решение ещё не отправляли)
export function useRunStatus(submissionId: string | null) {
  const [run, setRun] = useState<RunStatus | null>(null);
  // Сервер не ответил: показываем последний известный статус и пробуем снова
  const [isConnectionLost, setIsConnectionLost] = useState(false);
  // Ошибка, после которой спрашивать дальше бессмысленно
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setRun(null);
    setIsConnectionLost(false);
    setError(null);
    if (!submissionId) return;

    let stopped = false;
    let timerId: number | undefined;

    const poll = async () => {
      try {
        const data = await getSubmissionRun(submissionId);
        if (stopped) return;
        setRun(data);
        setIsConnectionLost(false);

        // Пока проверка в очереди или идёт, спрашиваем снова через столько, сколько сказал сервер.
        // finished и not_started — конечные состояния, опрос заканчивается
        if (data.state === 'queued' || data.state === 'running') {
          timerId = window.setTimeout(poll, (data.poll_after_seconds ?? 3) * 1000);
        }
      } catch (err) {
        if (stopped) return;
        if (err instanceof ApiError && err.status === 401) {
          setError('Сессия истекла. Войдите заново');
        } else if (err instanceof ApiError && err.status === 404) {
          setError('Отправка не найдена');
        } else {
          setIsConnectionLost(true);
          timerId = window.setTimeout(poll, RETRY_DELAY_MS);
        }
      }
    };

    poll();

    // Ушли со страницы или отправили новое решение — прекращаем опрос старого
    return () => {
      stopped = true;
      window.clearTimeout(timerId);
    };
  }, [submissionId]);

  return { run, isConnectionLost, error };
}