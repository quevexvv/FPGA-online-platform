import React from 'react';
import { Button, makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { CaretLeft20Filled, CaretRight20Filled } from '@fluentui/react-icons';

const WEEKDAYS = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

const useStyles = makeStyles({
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: '12px',
  },
  title: {
    margin: 0,
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  monthNav: {
    display: 'flex',
    alignItems: 'center',
  },
  monthName: {
    minWidth: '120px',
    textAlign: 'center',
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  arrow: {
    color: tokens.colorBrandForeground1,
  },
  box: {
    padding: '12px 14px',
    borderRadius: tokens.borderRadiusLarge,
    backgroundColor: tokens.colorNeutralBackground2,
  },
  // Сетка 7 колонок: дни недели и сами дни
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(7, 1fr)',
    rowGap: '4px',
    justifyItems: 'center',
  },
  weekday: {
    width: '100%',
    paddingBottom: '8px',
    marginBottom: '4px',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    textAlign: 'center',
    fontSize: '11px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground2,
  },
  day: {
    width: '32px',
    height: '32px',
    padding: 0,
    border: 'none',
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: 'transparent',
    fontFamily: 'inherit',
    fontSize: '13px',
    color: tokens.colorNeutralForeground1,
    cursor: 'pointer',
    ':hover': { backgroundColor: tokens.colorNeutralBackground1Hover },
    ':focus-visible': { outline: `2px solid ${tokens.colorStrokeFocus2}` },
    ':disabled': {
      color: tokens.colorNeutralForegroundDisabled,
      cursor: 'default',
      backgroundColor: 'transparent',
    },
  },
  today: {
    fontWeight: '700',
    color: tokens.colorBrandForeground1,
  },
  selected: {
    fontWeight: '700',
    color: tokens.colorNeutralForegroundOnBrand,
    backgroundColor: tokens.colorBrandBackground,
    ':hover': { backgroundColor: tokens.colorBrandBackgroundHover },
  },
});

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

// Все дни для сетки месяца: с понедельника перед 1-м числом до воскресенья после последнего
function monthDays(month: Date): Date[] {
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  // getDay(): 0 — воскресенье. Переводим в 0 — понедельник
  const offset = (first.getDay() + 6) % 7;
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  const cells = Math.ceil((offset + daysInMonth) / 7) * 7;
  return Array.from(
    { length: cells },
    (_, index) => new Date(month.getFullYear(), month.getMonth(), index - offset + 1),
  );
}

// «октябрь» → «Октябрь 2026»
function monthTitle(month: Date): string {
  const name = month.toLocaleString('ru-RU', { month: 'long' });
  return `${name[0].toUpperCase()}${name.slice(1)} ${month.getFullYear()}`;
}

interface MonthCalendarProps {
  month: Date; // какой месяц показываем (любой день этого месяца)
  selected: Date | null;
  minDate: Date; // раньше этого дня выбрать нельзя
  onSelect: (date: Date) => void;
  onMonthChange: (month: Date) => void;
}

// Календарь на месяц: стрелками листаем месяцы, кликом выбираем день
export const MonthCalendar: React.FC<MonthCalendarProps> = ({
  month,
  selected,
  minDate,
  onSelect,
  onMonthChange,
}) => {
  const styles = useStyles();
  const today = new Date();
  const minDay = new Date(minDate.getFullYear(), minDate.getMonth(), minDate.getDate());
  // В прошлые месяцы листать незачем
  const isFirstMonth =
    month.getFullYear() === minDay.getFullYear() && month.getMonth() === minDay.getMonth();

  const shiftMonth = (delta: number) =>
    onMonthChange(new Date(month.getFullYear(), month.getMonth() + delta, 1));

  return (
    <div>
      <div className={styles.header}>
        <h3 className={styles.title}>Выберите дату</h3>
        <div className={styles.monthNav}>
          <Button
            appearance="transparent"
            size="small"
            className={styles.arrow}
            icon={<CaretLeft20Filled />}
            aria-label="Предыдущий месяц"
            disabled={isFirstMonth}
            onClick={() => shiftMonth(-1)}
          />
          {/* aria-live: при смене месяца скринридер прочитает новое название */}
          <span className={styles.monthName} aria-live="polite">
            {monthTitle(month)}
          </span>
          <Button
            appearance="transparent"
            size="small"
            className={styles.arrow}
            icon={<CaretRight20Filled />}
            aria-label="Следующий месяц"
            onClick={() => shiftMonth(1)}
          />
        </div>
      </div>

      <div className={styles.box}>
        <div className={styles.grid}>
          {WEEKDAYS.map((weekday) => (
            <span key={weekday} className={styles.weekday} aria-hidden>
              {weekday}
            </span>
          ))}
          {monthDays(month).map((day) => {
            const isOutside = day.getMonth() !== month.getMonth();
            const isSelected = selected !== null && isSameDay(day, selected);
            return (
              <button
                key={day.toISOString()}
                type="button"
                className={mergeClasses(
                  styles.day,
                  isSameDay(day, today) && styles.today,
                  isSelected && styles.selected,
                )}
                // Дни соседних месяцев только заполняют сетку, выбрать их нельзя
                disabled={isOutside || day < minDay}
                aria-pressed={isSelected}
                aria-label={day.toLocaleDateString('ru-RU', {
                  day: 'numeric',
                  month: 'long',
                  weekday: 'long',
                })}
                onClick={() => onSelect(day)}
              >
                {day.getDate()}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
