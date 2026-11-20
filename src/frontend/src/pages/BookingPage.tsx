import React, { useState } from 'react';
import { Button, makeStyles, tokens } from '@fluentui/react-components';
import { BookingDialog } from '@/components/booking/BookingDialog';
import { SessionCard } from '@/components/booking/SessionCard';
import { SlotGrid } from '@/components/booking/SlotGrid';
import { slotLabel } from '@/components/booking/bookingTime';
import { getMockSlots, mockSessionEndsAt } from '@/components/booking/bookingMock';

const useStyles = makeStyles({
  page: {
    height: '100%',
    boxSizing: 'border-box',
    padding: '24px 32px',
    overflowY: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: '32px',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  sectionTitle: {
    margin: '0 0 20px',
    fontSize: '18px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  actions: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: '16px',
    marginTop: '32px',
  },
  actionButton: {
    minWidth: '280px',
  },
  notice: {
    margin: 0,
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
});

export const BookingPage: React.FC = () => {
  const styles = useStyles();
  // TODO: слоты и сессия пока ненастоящие, см. bookingMock.ts
  const [todaySlots] = useState(() => getMockSlots(new Date()));
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const selectedSlot = todaySlots.find((slot) => slot.id === selectedId) ?? null;

  // TODO: здесь будет запрос на бронь, пока просто сообщаем, что выбрано
  const handleBook = () => {
    if (selectedSlot) {
      setNotice(`Выбран слот ${slotLabel(selectedSlot)} на сегодня. Бронь заработает вместе с API`);
    }
  };

  const handleDialogConfirm = (date: Date, timeLabel: string) => {
    const day = date.toLocaleDateString('ru-RU', { day: 'numeric', month: 'long' });
    setNotice(`Выбрано время ${timeLabel}, ${day}. Бронь заработает вместе с API`);
    setIsDialogOpen(false);
  };

  return (
    <div className={styles.page}>
      <SessionCard endsAt={mockSessionEndsAt} />

      <section aria-labelledby="today-slots-title">
        <h2 id="today-slots-title" className={styles.sectionTitle}>
          Доступные временные слоты (сегодня)
        </h2>
        <SlotGrid slots={todaySlots} selectedId={selectedId} onSelect={setSelectedId} />

        <div className={styles.actions}>
          <Button
            className={styles.actionButton}
            appearance="primary"
            size="large"
            disabled={!selectedSlot}
            onClick={handleBook}
          >
            Забронировать слот
          </Button>
          <Button
            className={styles.actionButton}
            appearance="primary"
            size="large"
            onClick={() => setIsDialogOpen(true)}
          >
            Выбрать другое время
          </Button>
          {/* aria-live: скринридер прочитает сообщение, когда оно появится */}
          <p className={styles.notice} aria-live="polite">
            {notice}
          </p>
        </div>
      </section>

      <BookingDialog
        open={isDialogOpen}
        onOpenChange={setIsDialogOpen}
        onConfirm={handleDialogConfirm}
      />
    </div>
  );
};
