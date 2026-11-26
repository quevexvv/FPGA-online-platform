import React from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { BookingSlot } from '@/types';
import { slotLabel } from './bookingTime';

const useStyles = makeStyles({
  // Колонки по 360px и шире: на большом экране три в ряд, на узком меньше
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(min(360px, 100%), 1fr))',
    gap: '24px',
    maxWidth: '1400px',
  },
  slot: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: '10px',
    padding: '26px 28px',
    backgroundColor: tokens.colorNeutralBackground1,
    // Рамка есть всегда, но прозрачная: при выборе карточка не прыгает на 2px
    border: '2px solid transparent',
    borderRadius: tokens.borderRadiusXLarge,
    fontFamily: 'inherit',
    textAlign: 'left',
    cursor: 'pointer',
    ':hover': { border: `2px solid ${tokens.colorNeutralStroke1}` },
    ':focus-visible': {
      outline: `2px solid ${tokens.colorStrokeFocus2}`,
      outlineOffset: '2px',
    },
  },
  selected: {
    border: `2px solid ${tokens.colorBrandStroke1}`,
    ':hover': { border: `2px solid ${tokens.colorBrandStroke1}` },
  },
  time: {
    fontSize: '18px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  status: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    fontSize: '13px',
    fontWeight: '600',
    // Точка перед словом «Свободно» или «Занято» в цвет текста
    '::before': {
      content: '""',
      width: '8px',
      height: '8px',
      borderRadius: '50%',
      backgroundColor: 'currentColor',
    },
  },
  free: { color: tokens.colorBrandForeground1 },
  empty: {
    margin: 0,
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
});

interface SlotGridProps {
  slots: BookingSlot[];
  selectedId: string | null;
  onSelect: (slotId: string) => void;
}

// Карточки доступных для бронирования слотов
export const SlotGrid: React.FC<SlotGridProps> = ({ slots, selectedId, onSelect }) => {
  const styles = useStyles();

  if (slots.length === 0) {
    return <p className={styles.empty}>На сегодня нет свободных слотов</p>;
  }

  return (
    <div className={styles.grid} role="group" aria-label="Слоты на сегодня">
      {slots.map((slot) => (
        <button
          key={slot.id}
          type="button"
          className={mergeClasses(styles.slot, slot.id === selectedId && styles.selected)}
          aria-pressed={slot.id === selectedId}
          onClick={() => onSelect(slot.id)}
        >
          <span className={styles.time}>{slotLabel(slot)}</span>
          <span className={mergeClasses(styles.status, styles.free)}>Свободно</span>
        </button>
      ))}
    </div>
  );
};
