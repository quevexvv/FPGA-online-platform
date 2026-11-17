import { BookingSlot } from '@/types';
import { toDateKey } from './bookingTime';

/*
  TODO: брони пока нет в API, поэтому данные ненастоящие.
  Когда бэкенд её сделает, слоты и текущая сессия придут с сервера,
  и этот файл можно будет удалить.
*/

const SLOT_TIMES = [
  ['14:00', '14:30'],
  ['14:30', '15:00'],
  ['15:00', '15:30'],
  ['15:30', '16:00'],
  ['16:00', '16:30'],
  ['16:30', '17:00'],
];

// Слоты на выбранный день. Занятость «случайная», но одинаковая для одной даты,
// чтобы макет не менялся при каждой перерисовке
export function getMockSlots(date: Date): BookingSlot[] {
  return SLOT_TIMES.map(([start, end], index) => ({
    id: `${toDateKey(date)}T${start}`,
    start,
    end,
    isBusy: (date.getDate() + index) % 3 === 0,
  }));
}

// Текущая сессия студента: заканчивается через 12 минут 45 секунд после открытия сайта
export const mockSessionEndsAt = new Date(Date.now() + (12 * 60 + 45) * 1000);
