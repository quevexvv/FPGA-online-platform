import { SubmissionSummary } from '../types';
import { apiRequest } from './client';

// Отправить код решения. Сервер пока только сохраняет его, проверка на плате появится позже
export function submitSolution(labId: string, sourceCode: string): Promise<SubmissionSummary> {
  return apiRequest<SubmissionSummary>(`/labs/${encodeURIComponent(labId)}/submissions`, {
    method: 'POST',
    body: { source_code: sourceCode },
    withCsrf: true,
  });
}