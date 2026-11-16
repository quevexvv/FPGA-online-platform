import React from 'react';
import { makeStyles, mergeClasses } from '@fluentui/react-components';
import boardImage from '@/assets/fpga-board.svg';
import {
  BOARD_HEIGHT,
  BOARD_WIDTH,
  BoardState,
  isBitSet,
  isLedMismatch,
  LedPin,
  leds,
  mismatchedLeds,
  SwitchPin,
  switches,
} from './boardLayout';

// Цвета — это цвета настоящей платы, а не интерфейса, поэтому от темы они не зависят
const ledColors = {
  red: { on: '#FF4A3D', off: '#5C2A2E' },
  green: { on: '#3DDC84', off: '#1F4A35' },
};
// Рамка несовпадения жёлтая: так её не спутать ни с красным, ни с зелёным светодиодом
const MISMATCH_COLOR = '#FFC83D';

// Верх светодиодов и переключателей на картинке
const LED_Y = 370;
const SWITCH_Y = 396;

const useStyles = makeStyles({
  // Ширину плата берёт у родителя, а высоту считает сама по viewBox.
  // Ограничить высоту можно снаружи через className
  board: {
    display: 'block',
    width: '100%',
  },
});

// Один светодиод: тусклый, когда выключен, и со свечением, когда горит
const Led: React.FC<{ led: LedPin; state: BoardState | null }> = ({ led, state }) => {
  const isOn = state !== null && isBitSet(state.dout, led.bit);
  const isMismatch = state !== null && isLedMismatch(state, led);
  const colors = ledColors[led.color];

  // Подсказка при наведении: что горит и что ожидалось
  let hint = `${led.name}: ${isOn ? 'горит' : 'не горит'}`;
  if (state && !isBitSet(state.mask, led.bit)) hint += ', не проверяется';
  else if (isMismatch) hint += `, ожидалось: ${isOn ? 'не горит' : 'горит'}`;

  return (
    <g>
      <title>{hint}</title>
      {/* Свечение — два полупрозрачных прямоугольника побольше под самим светодиодом */}
      {isOn && (
        <>
          <rect
            x={led.x - 9.5}
            y={LED_Y - 6.5}
            width={19}
            height={23}
            rx={7}
            fill={colors.on}
            fillOpacity={0.18}
          />
          <rect
            x={led.x - 6.5}
            y={LED_Y - 3.5}
            width={13}
            height={17}
            rx={4}
            fill={colors.on}
            fillOpacity={0.45}
          />
        </>
      )}
      <rect
        x={led.x - 3.5}
        y={LED_Y - 0.5}
        width={7}
        height={11}
        fill={isOn ? colors.on : colors.off}
        stroke="white"
      />
      {/* Блик, чтобы светодиод выглядел объёмным */}
      <rect
        x={led.x - 1}
        y={LED_Y + 2}
        width={2}
        height={3}
        fill="white"
        fillOpacity={isOn ? 1 : 0.25}
      />
      {isMismatch && (
        <rect
          x={led.x - 7.5}
          y={LED_Y - 4.5}
          width={15}
          height={19}
          rx={3.5}
          fill="none"
          stroke={MISMATCH_COLOR}
          strokeWidth={1.5}
        />
      )}
    </g>
  );
};

// Один переключатель: рычажок вверху — 1, внизу — 0
const Switch: React.FC<{ pin: SwitchPin; state: BoardState | null }> = ({ pin, state }) => {
  const isOn = state !== null && isBitSet(state.din, pin.bit);
  const knobY = isOn ? SWITCH_Y : SWITCH_Y + 20;

  return (
    <g>
      <title>{`${pin.name}: ${isOn ? 1 : 0}`}</title>
      {/* Прорезь закрывает рычажок, нарисованный на картинке, и мы рисуем свой */}
      <rect x={pin.x - 8} y={SWITCH_Y} width={16} height={40} fill="#848484" />
      <rect x={pin.x - 7} y={knobY} width={14} height={20} fill="black" />
      {/* Рифление на рычажке */}
      {[3.7, 7.6, 11.5, 15.4].map((offset) => (
        <line
          key={offset}
          x1={pin.x - 7}
          x2={pin.x + 7}
          y1={knobY + offset}
          y2={knobY + offset}
          stroke="#5B5B5B"
          strokeWidth={0.5}
        />
      ))}
    </g>
  );
};

// Описание для скринридера: картинку он не видит, поэтому пересказываем её словами
function describeBoard(state: BoardState | null): string {
  if (!state) return 'Отладочная плата с ПЛИС. Результата тестов пока нет';
  const switchBits = switches.map((pin) => (isBitSet(state.din, pin.bit) ? 1 : 0)).join('');
  const litLeds = leds.filter((led) => isBitSet(state.dout, led.bit)).map((led) => led.name);
  const mismatches = mismatchedLeds(state);
  return [
    `Переключатели SW9–SW0: ${switchBits}`,
    `Горят: ${litLeds.length > 0 ? litLeds.join(', ') : 'ни один светодиод'}`,
    mismatches.length > 0 ? `Не совпали: ${mismatches.join(', ')}` : 'Все светодиоды как ожидалось',
  ].join('. ');
}

interface FpgaBoardProps {
  // Состояние в выбранном тесте; null — плата «выключена», тестов ещё нет
  state: BoardState | null;
  className?: string;
}

// Плата: картинка снизу, поверх неё рисуем переключатели и светодиоды по данным теста
export const FpgaBoard: React.FC<FpgaBoardProps> = ({ state, className }) => {
  const styles = useStyles();

  return (
    <svg
      className={mergeClasses(styles.board, className)}
      viewBox={`0 0 ${BOARD_WIDTH} ${BOARD_HEIGHT}`}
      role="img"
      aria-label={describeBoard(state)}
    >
      <image href={boardImage} width={BOARD_WIDTH} height={BOARD_HEIGHT} />
      {switches.map((pin) => (
        <Switch key={pin.name} pin={pin} state={state} />
      ))}
      {leds.map((led) => (
        <Led key={led.name} led={led} state={state} />
      ))}
    </svg>
  );
};
