import { RunStatus, SubmissionSummary } from '@/types';
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