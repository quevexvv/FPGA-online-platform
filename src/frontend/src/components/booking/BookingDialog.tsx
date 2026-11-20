import React, { useState } from 'react';
import {
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Input,
  makeStyles,
  mergeClasses,
  tokens,
} from '@fluentui/react-components';
import { Dismiss24Regular } from '@fluentui/react-icons';
import { getMockSlots } from './bookingMock';
import { MonthCalendar } from './MonthCalendar';
import { addMinutes, slotLabel } from './bookingTime';

// Минимальная длина сессии, как подсказка на макете
const SESSION_MINUTES = 30;

const useStyles = makeStyles({
  surface: {
    maxWidth: '840px',
    width: 'calc(100vw - 32px)',
  },
  // Две колонки: слева календарь, справа время
  content: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)',
    gap: '24px',
    paddingTop: '8px',
    minHeight: '320px',
  },
  sectionTitle: {
    margin: '0 0 12px',
    fontSize: '14px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  chips: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '8px',
    marginBottom: '24px',
  },
  chip: {
    padding: '6px 12px',
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: tokens.colorNeutralBackground2,
    fontFamily: 'inherit',
    fontSize: '13px',
    color: tokens.colorNeutralForeground1,
    cursor: 'pointer',
    ':hover': { border: `1px solid ${tokens.colorNeutralStroke1}` },
    ':focus-visible': { outline: `2px solid ${tokens.colorStrokeFocus2}` },
    ':disabled': {
      color: tokens.colorNeutralForegroundDisabled,
      backgroundColor: tokens.colorNeutralBackground3,
      cursor: 'not-allowed',
    },
  },
  chipSelected: {
    fontWeight: '600',
    color: tokens.colorBrandForeground1,
    backgroundColor: tokens.colorStatusSuccessBackground1,
    border: `1px solid ${tokens.colorBrandStroke1}`,
    ':hover': { border: `1px solid ${tokens.colorBrandStroke1}` },
  },
  timeInput: {
    width: '100%',
  },
  hint: {
    margin: '6px 0 0',
    fontSize: '12px',
    color: tokens.colorNeutralForeground2,
  },
});

interface BookingDialogContentProps {
  onConfirm: (date: Date, timeLabel: string) => void;
}

// Содержимое окна. Fluent рисует его только пока окно открыто,
// поэтому при каждом открытии выбор начинается заново, без ручного сброса
const BookingDialogContent: React.FC<BookingDialogContentProps> = ({ onConfirm }) => {
  const styles = useStyles();
  const [today] = useState(() => new Date());
  const [month, setMonth] = useState(today);
  const [date, setDate] = useState(today);
  const [slotId, setSlotId] = useState<string | null>(null);
  const [manualTime, setManualTime] = useState('');

  const slots = getMockSlots(date);
  const selectedSlot = slots.find((slot) => slot.id === slotId) ?? null;
  // Выбрать можно либо готовый слот, либо своё время: что выбрали последним, то и берём
  const timeLabel = selectedSlot
    ? slotLabel(selectedSlot)
    : manualTime
      ? `${manualTime} – ${addMinutes(manualTime, SESSION_MINUTES)}`
      : null;

  const handleDateSelect = (newDate: Date) => {
    setDate(newDate);
    // У другого дня свои слоты, прежний выбор к нему не относится
    setSlotId(null);
  };

  const handleSlotSelect = (id: string) => {
    setSlotId(id);
    setManualTime('');
  };

  const handleManualTime = (value: string) => {
    setManualTime(value);
    setSlotId(null);
  };

  return (
    <DialogBody>
      <DialogTitle
        action={
          <DialogTrigger action="close">
            <Button appearance="subtle" aria-label="Закрыть" icon={<Dismiss24Regular />} />
          </DialogTrigger>
        }
      >
        Выбор другого времени
      </DialogTitle>

      <DialogContent className={styles.content}>
        <MonthCalendar
          month={month}
          selected={date}
          minDate={today}
          onSelect={handleDateSelect}
          onMonthChange={setMonth}
        />

        <div>
          <h3 className={styles.sectionTitle}>
            Доступные слоты на {date.toLocaleDateString('ru-RU', { day: 'numeric', month: 'long' })}
          </h3>
          <div className={styles.chips} role="group" aria-label="Слоты на выбранный день">
            {slots.map((slot) => (
              <button
                key={slot.id}
                type="button"
                className={mergeClasses(styles.chip, slot.id === slotId && styles.chipSelected)}
                disabled={slot.isBusy}
                aria-pressed={slot.id === slotId}
                onClick={() => handleSlotSelect(slot.id)}
              >
                {slotLabel(slot)}
              </button>
            ))}
          </div>

          <h3 className={styles.sectionTitle}>
            <label htmlFor="booking-manual-time">Или введите удобное время вручную</label>
          </h3>
          <Input
            id="booking-manual-time"
            className={styles.timeInput}
            type="time"
            value={manualTime}
            onChange={(_, data) => handleManualTime(data.value)}
          />
          <p className={styles.hint}>
            {manualTime
              ? `Сессия: ${manualTime} – ${addMinutes(manualTime, SESSION_MINUTES)}. `
              : ''}
            Минимальный шаг сессии: {SESSION_MINUTES} минут
          </p>
        </div>
      </DialogContent>

      <DialogActions>
        <DialogTrigger action="close">
          <Button appearance="secondary">Отмена</Button>
        </DialogTrigger>
        <Button
          appearance="primary"
          disabled={timeLabel === null}
          onClick={() => timeLabel && onConfirm(date, timeLabel)}
        >
          Подтвердить
        </Button>
      </DialogActions>
    </DialogBody>
  );
};

interface BookingDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: (date: Date, timeLabel: string) => void;
}

// Окно «Выбор другого времени»: день в календаре и слот или своё время
export const BookingDialog: React.FC<BookingDialogProps> = ({ open, onOpenChange, onConfirm }) => {
  const styles = useStyles();

  return (
    <Dialog open={open} onOpenChange={(_, data) => onOpenChange(data.open)}>
      <DialogSurface className={styles.surface}>
        <BookingDialogContent onConfirm={onConfirm} />
      </DialogSurface>
    </Dialog>
  );
};
