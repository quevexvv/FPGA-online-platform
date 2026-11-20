import { useEffect, useState } from 'react';
import { ApiError } from '@/api/client';
import { getLab } from '@/api/labs';
import { getSubmission } from '@/api/submissions';
import { LabDetail, SubmissionDetail } from '@/types';

interface SubmissionState {
  submissionId: string | undefined; // к какой отправке относятся данные ниже
  submission: SubmissionDetail | null; // null — данные ещё не пришли
  lab: LabDetail | null; // лабораторная этой отправки, нужна ради названия
  error: string | null;
  isNotFound: boolean;
}

function emptyState(submissionId: string | undefined): SubmissionState {
  return { submissionId, submission: null, lab: null, error: null, isNotFound: false };
}

// Загружает отправленное решение и его лабораторную: для страницы отчёта
export function useSubmission(submissionId: string | undefined) {
  const [state, setState] = useState<SubmissionState>(() => emptyState(submissionId));
  const [reloadCount, setReloadCount] = useState(0);

  useEffect(() => {
    if (!submissionId) return;
    let ignore = false;

    const load = async () => {
      try {
        const submission = await getSubmission(submissionId);
        // Без названия лабораторной отчёт всё равно полезен, поэтому её ошибку не считаем ошибкой
        const lab = await getLab(submission.lab_id).catch(() => null);
        if (!ignore) setState({ ...emptyState(submissionId), submission, lab });
      } catch (err) {
        if (ignore) return;
        // 404 — такой отправки нет или она чужая, 422 — в адресе вообще не UUID
        if (err instanceof ApiError && (err.status === 404 || err.status === 422)) {
          setState({ ...emptyState(submissionId), isNotFound: true });
        } else {
          setState({ ...emptyState(submissionId), error: 'Не удалось загрузить отчёт' });
        }
      }
    };
    load();

    return () => {
      ignore = true;
    };
  }, [submissionId, reloadCount]);

  const retry = () => {
    setState(emptyState(submissionId));
    setReloadCount((count) => count + 1);
  };

  const current = state.submissionId === submissionId ? state : emptyState(submissionId);
  return { ...current, retry };
}
