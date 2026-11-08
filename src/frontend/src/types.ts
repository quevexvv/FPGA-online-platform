export type TabType = 'labs' | 'workspace' | 'booking' | 'history';
export type PageType = TabType | 'lab-task';
export type LabStatus = 'completed' | 'in_progress' | 'not_started';

export interface LabItem {
  id: number;
  title: string;
  subtitle: string;
  description: string;
  deadline: string;
  deadlineType: 'completed' | 'today' | 'future';
  status: LabStatus;
  isLocked: boolean;
}