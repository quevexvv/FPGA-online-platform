import { useEffect, useState } from 'react';
import { getLabs } from '@/api/labs';
import { getLabSubmissions } from '@/api/submissions';
import { SubmissionSummary } from '@/types';

// Строка истории: отправка и название её лабораторной
export interface HistoryItem {
  submission: SubmissionSummary;
  labTitle: string;
}

// Сколько последних отправок берём по каждой лабораторной
const PER_LAB_LIMIT = 20;

/*
  Все отправки студента, от новых к старым.
  TODO: общего списка в API пока нет, поэтому собираем его сами:
  берём лабораторные, по каждой — её отправки, склеиваем и сортируем.
  Когда бэкенд сделает GET /submissions, хватит одного запроса.
*/
export function useHistory() {
  const [items, setItems] = useState<HistoryItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reloadCount, setReloadCount] = useState(0);

  useEffect(() => {
    let ignore = false;

    const load = async () => {
      try {
        const labs = await getLabs();
        // Запросы по всем лабораторным уходят одновременно, Promise.all ждёт, пока придут все
        const perLab = await Promise.all(
          labs.map(async (lab) => {
            const submissions = await getLabSubmissions(lab.id, PER_LAB_LIMIT);
            return submissions.map((submission) => ({ submission, labTitle: lab.title }));
          }),
        );
        // flat() склеивает массивы лабораторных в один, сортируем от новых к старым
        const all = perLab
          .flat()
          .sort(
            (a, b) => Date.parse(b.submission.created_at) - Date.parse(a.submission.created_at),
          );
        if (!ignore) setItems(all);
      } catch {
        if (!ignore) setError('Не удалось загрузить историю');
      }
    };
    load();

    return () => {
      ignore = true;
    };
  }, [reloadCount]);

  // Ошибку и старые данные сбрасываем здесь, в обработчике кнопки, а не в эффекте
  const retry = () => {
    setError(null);
    setItems(null);
    setReloadCount((count) => count + 1);
  };

  return { items, error, retry };
}
