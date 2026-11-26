import React, { useEffect, useState } from 'react';
import { makeStyles, tokens } from '@fluentui/react-components';
import { Timer24Regular, CheckmarkCircle24Regular, Warning24Regular } from '@fluentui/react-icons';
import { BoardSession } from '@/types';

const useStyles = makeStyles({
  card: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: '24px',
    padding: '28px 32px',
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    flexWrap: 'wrap',
  },
  label: {
    margin: '0 0 12px',
    fontSize: '12px',
    fontWeight: '600',
    letterSpacing: '0.04em',
    textTransform: 'uppercase',
    color: tokens.colorNeutralForeground2,
  },
  title: {
    margin: 0,
    fontSize: '20px',
    fontWeight: '700',
    color: tokens.colorNeutralForeground1,
  },
  empty: {
    margin: 0,
    fontSize: '15px',
    color: tokens.colorNeutralForeground2,
  },
  timer: {
    flexShrink: 0,
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
  },
  timerLabel: {
    fontSize: '13px',
    color: tokens.colorNeutralForeground2,
  },
  timerValue: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontSize: '28px',
    fontWeight: '700',
    // Цифры одной ширины: таймер не дёргается, когда меняются секунды
    fontVariantNumeric: 'tabular-nums',
    color: tokens.colorStatusWarningForeground1,
  },
  free: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontSize: '20px',
    fontWeight: '600',
    color: tokens.colorStatusSuccessForeground1,
  },
  offline: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontSize: '20px',
    fontWeight: '600',
    color: tokens.colorStatusDangerForeground1,
  },
});

// «Иванов Иван Иванович» → «Иванов И. И.»
function shortName(fullName: string): string {
  const [lastName, ...rest] = fullName.trim().split(/\s+/);
  const initials = rest.map((part) => `${part[0]}.`).join(' ');
  return initials ? `${lastName} ${initials}` : lastName;
}

// Оставшееся время: 765 секунд → «12:45», больше часа → «1:02:03»
function formatRemaining(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const mmss = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  return hours > 0 ? `${hours}:${mmss}` : mmss;
}

// Текущее время, которое обновляется раз в секунду: для обратного отсчёта
function useNow(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timerId = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timerId);
  }, []);
  return now;
}

interface SessionCardProps {
  session: BoardSession;
  isDemo?: boolean;
}

// Текущее состояние стенда и оставшееся время сессии
export const SessionCard: React.FC<SessionCardProps> = ({ session, isDemo = false }) => {
  const styles = useStyles();
  const now = useNow();

  const label = isDemo ? 'Текущая сессия (демо)' : 'Текущая сессия';

  if (session.status === 'free') {
    return (
      <section className={styles.card} aria-label="Состояние стенда">
        <div>
          <p className={styles.label}>{label}</p>
          <p className={styles.empty}>Нет активной сессии</p>
        </div>

        <span className={styles.free}>
          <CheckmarkCircle24Regular aria-hidden />
          Плата свободна
        </span>
      </section>
    );
  }

  if (session.status === 'offline') {
    return (
      <section className={styles.card} aria-label="Состояние стенда">
        <div>
          <p className={styles.label}>{label}</p>
          <p className={styles.empty}>Стенд не в сети</p>
        </div>

        <span className={styles.offline}>
          <Warning24Regular aria-hidden />
          Плата недоступна
        </span>
      </section>
    );
  }

  const remainingSeconds = Math.max(0, Math.ceil((session.endsAt.getTime() - now) / 1000));

  return (
    <section className={styles.card} aria-label="Текущая сессия">
      <div>
        <p className={styles.label}>{label}</p>

        <h1 className={styles.title}>
          Студент: {shortName(session.studentName)}
          {session.group && ` (гр. ${session.group})`}
        </h1>
      </div>

      <div className={styles.timer}>
        <span className={styles.timerLabel}>
          {remainingSeconds > 0 ? 'До окончания сессии:' : 'Ожидаем обновления статуса:'}
        </span>

        <span className={styles.timerValue} role="timer">
          <Timer24Regular aria-hidden />
          {formatRemaining(remainingSeconds)}
        </span>
      </div>
    </section>
  );
};
