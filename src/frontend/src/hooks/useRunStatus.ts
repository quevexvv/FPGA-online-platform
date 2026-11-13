import { useEffect, useState } from 'react';
import { ApiError } from '@/api/client';
import { getSubmissionRun } from '@/api/submissions';
import { RunStatus } from '@/types';

// Через сколько повторить запрос, если сервер не ответил
const RETRY_DELAY_MS = 5000;

interface RunStatusState {
  submissionId: string | null; // к какой отправке относятся данные ниже
  run: RunStatus | null;
  // Сервер не ответил: показываем последний известный статус и пробуем снова
  isConnectionLost: boolean;
  // Ошибка, после которой спрашивать дальше бессмысленно
  error: string | null;
}

function emptyState(submissionId: string | null): RunStatusState {
  return { submissionId, run: null, isConnectionLost: false, error: null };
}

// Следит за проверкой отправленного решения: спрашивает сервер, пока проверка идёт.
// submissionId = null — следить не за чем (решение ещё не отправляли)
export function useRunStatus(submissionId: string | null) {
  const [state, setState] = useState<RunStatusState>(() => emptyState(null));

  useEffect(() => {
    if (!submissionId) return;

    let stopped = false;
    let timerId: number | undefined;

    const poll = async () => {
      try {
        const data = await getSubmissionRun(submissionId);
        if (stopped) return;
        setState({ submissionId, run: data, isConnectionLost: false, error: null });

        // Пока проверка в очереди или идёт, спрашиваем снова через столько, сколько сказал сервер.
        // finished и not_started — конечные состояния, опрос заканчивается
        if (data.state === 'queued' || data.state === 'running') {
          timerId = window.setTimeout(poll, (data.poll_after_seconds ?? 3) * 1000);
        }
      } catch (err) {
        if (stopped) return;
        if (err instanceof ApiError && err.status === 401) {
          setState({ ...emptyState(submissionId), error: 'Сессия истекла. Войдите заново' });
        } else if (err instanceof ApiError && err.status === 404) {
          setState({ ...emptyState(submissionId), error: 'Отправка не найдена' });
        } else {
          // Последний известный статус этой отправки оставляем на экране
          setState((prev) => ({
            ...(prev.submissionId === submissionId ? prev : emptyState(submissionId)),
            isConnectionLost: true,
          }));
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

  // Пока по новой отправке ответа нет, данные старой не показываем
  const current = state.submissionId === submissionId ? state : emptyState(submissionId);
  return { run: current.run, isConnectionLost: current.isConnectionLost, error: current.error };
}