import { RunStatus, SubmissionDetail, SubmissionSummary } from '@/types';
import { apiRequest } from './client';

// Отправить код решения. Сервер сохраняет его и ставит проверку в очередь
export function submitSolution(labId: string, sourceCode: string): Promise<SubmissionSummary> {
  return apiRequest<SubmissionSummary>(`/labs/${encodeURIComponent(labId)}/submissions`, {
    method: 'POST',
    body: { source_code: sourceCode },
    withCsrf: true,
  });
}

// Последняя попытка проверки отправленного решения. Только чтение, поэтому без CSRF
export function getSubmissionRun(submissionId: string): Promise<RunStatus> {
  return apiRequest<RunStatus>(`/submissions/${encodeURIComponent(submissionId)}/run`);
}

// Одно отправленное решение вместе с кодом: для отчёта о проверке
export function getSubmission(submissionId: string): Promise<SubmissionDetail> {
  return apiRequest<SubmissionDetail>(`/submissions/${encodeURIComponent(submissionId)}`);
}

// Отправки по лабораторной, от новых к старым. Сервер отдаёт не больше 100 за раз
export function getLabSubmissions(labId: string, limit = 20): Promise<SubmissionSummary[]> {
  return apiRequest<SubmissionSummary[]>(
    `/labs/${encodeURIComponent(labId)}/submissions?limit=${limit}`,
  );
}

// Последнее отправленное решение по лабораторной вместе с кодом. null — ещё не отправляли
export async function getLatestSubmission(labId: string): Promise<SubmissionDetail | null> {
  // Сервер отдаёт список от новых к старым, поэтому достаточно первой записи
  const list = await getLabSubmissions(labId, 1);
  if (list.length === 0) return null;
  return getSubmission(list[0].id);
}
