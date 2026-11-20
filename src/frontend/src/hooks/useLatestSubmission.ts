import { useEffect, useState } from 'react';
import { getLatestSubmission } from '@/api/submissions';
import { SubmissionDetail } from '@/types';

interface LatestState {
  labId: string | undefined; // к какой лабораторной относятся данные ниже
  submission: SubmissionDetail | null;
  isLoaded: boolean;
}

// Последнее отправленное решение: чтобы после перезагрузки страницы вернуть код и статус проверки
export function useLatestSubmission(labId: string | undefined) {
  const [state, setState] = useState<LatestState>({ labId, submission: null, isLoaded: false });

  useEffect(() => {
    if (!labId) return;
    let ignore = false;

    getLatestSubmission(labId)
      .then((submission) => {
        if (!ignore) setState({ labId, submission, isLoaded: true });
      })
      .catch(() => {
        // Не получилось — не страшно: студент просто начнёт с шаблона
        if (!ignore) setState({ labId, submission: null, isLoaded: true });
      });

    return () => {
      ignore = true;
    };
  }, [labId]);

  const isCurrent = state.labId === labId;
  return {
    submission: isCurrent ? state.submission : null,
    isLoaded: isCurrent && state.isLoaded,
  };
}
