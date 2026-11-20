import { useEffect, useState } from 'react';
import { ApiError } from '@/api/client';
import { getLab } from '@/api/labs';
import { LabDetail } from '@/types';

interface LabState {
  labId: string | undefined; // к какой лабораторной относятся данные ниже
  lab: LabDetail | null; // null — данные ещё не пришли
  error: string | null;
  // Ошибку «не найдено» показываем без кнопки «Повторить»: повтор не поможет
  isNotFound: boolean;
}

function emptyState(labId: string | undefined): LabState {
  return { labId, lab: null, error: null, isNotFound: false };
}

// Загружает лабораторную по id. Нужна и странице задания, и рабочему пространству
export function useLab(labId: string | undefined) {
  const [state, setState] = useState<LabState>(() => emptyState(labId));
  // Счётчик попыток: увеличиваем его, чтобы загрузить заново
  const [reloadCount, setReloadCount] = useState(0);

  useEffect(() => {
    if (!labId) return;
    let ignore = false;

    getLab(labId)
      .then((lab) => {
        if (!ignore) setState({ ...emptyState(labId), lab });
      })
      .catch((err) => {
        if (ignore) return;
        // 404 — такой работы нет, 422 — в адресе вообще не UUID
        if (err instanceof ApiError && (err.status === 404 || err.status === 422)) {
          setState({ ...emptyState(labId), isNotFound: true });
        } else {
          setState({ ...emptyState(labId), error: 'Не удалось загрузить задание' });
        }
      });

    return () => {
      ignore = true;
    };
  }, [labId, reloadCount]);

  // Повтор: сбрасываем ошибку (появится загрузка) и запускаем эффект заново
  const retry = () => {
    setState(emptyState(labId));
    setReloadCount((count) => count + 1);
  };

  // Пока по новой лабораторной ответа нет, данные прошлой не показываем
  const current = state.labId === labId ? state : emptyState(labId);
  return { lab: current.lab, error: current.error, isNotFound: current.isNotFound, retry };
}
