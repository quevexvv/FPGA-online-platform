import { BookingSlot } from '@/types';

// Мелкие функции для времени брони. Лежат отдельно от компонентов:
// файл с компонентами должен экспортировать только компоненты, иначе ломается Fast Refresh

// «14:00 – 14:30»
export function slotLabel(slot: BookingSlot): string {
  return `${slot.start} – ${slot.end}`;
}

// '18:00' + 30 минут → '18:30'
export function addMinutes(time: string, minutes: number): string {
  const [hours, mins] = time.split(':').map(Number);
  const total = (hours * 60 + mins + minutes) % (24 * 60);
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}

// Дата в виде '2026-11-18' по местному времени: удобно как ключ
export function toDateKey(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}
