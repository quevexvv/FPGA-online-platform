import { LabDetail, LabSummary } from '@/types';
import { apiRequest } from './client';

// Список опубликованных лабораторных (краткие карточки для таблицы)
export function getLabs(): Promise<LabSummary[]> {
  return apiRequest<LabSummary[]>('/labs');
}

// Одна лабораторная целиком: условие, описание интерфейса и шаблон кода
export function getLab(labId: string): Promise<LabDetail> {
  // encodeURIComponent защищает адрес, если в id окажутся символы вроде "/" или "?"
  return apiRequest<LabDetail>(`/labs/${encodeURIComponent(labId)}`);
}
