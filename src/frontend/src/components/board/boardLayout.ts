import { RunTest } from '@/types';

// Раскладка платы Terasic C5G на картинке fpga-board.svg.
// Координаты взяты из самой картинки, поэтому работают в её системе: 652 × 455
export const BOARD_WIDTH = 652;
export const BOARD_HEIGHT = 455;

// Светодиоды и переключатели стоят с шагом 32: центр первого на x = 54
const FIRST_CENTER_X = 54;
const STEP_X = 32;

export interface LedPin {
  name: string; // подпись на плате, например LEDR3
  bit: number; // номер бита в dout
  color: 'red' | 'green';
  x: number; // центр светодиода на картинке
}

export interface SwitchPin {
  name: string; // например SW9
  bit: number; // номер бита в din
  x: number; // центр переключателя на картинке
}

// Слева направо: LEDR9 … LEDR0 (dout[9..0]), затем LEDG7 … LEDG0 (dout[17..10])
export const leds: LedPin[] = Array.from({ length: 18 }, (_, index) => {
  const isRed = index < 10;
  const number = isRed ? 9 - index : 17 - index;
  return {
    name: isRed ? `LEDR${number}` : `LEDG${number}`,
    bit: isRed ? number : 10 + number,
    color: isRed ? 'red' : 'green',
    x: FIRST_CENTER_X + STEP_X * index,
  };
});

// Слева направо: SW9 … SW0 (din[9..0])
export const switches: SwitchPin[] = Array.from({ length: 10 }, (_, index) => ({
  name: `SW${9 - index}`,
  bit: 9 - index,
  x: FIRST_CENTER_X + STEP_X * index,
}));

// Сервер присылает числа строками вида '0x003'. parseInt с основанием 16 понимает префикс 0x
export function parseHex(value: string): number {
  return Number.parseInt(value, 16);
}

// Включён ли бит с номером bit: сдвигаем его в младший разряд и смотрим на него
export function isBitSet(value: number, bit: number): boolean {
  return ((value >> bit) & 1) === 1;
}

// Состояние платы в одном тесте: что на переключателях и что со светодиодами
export interface BoardState {
  din: number;
  dout: number;
  expected: number;
  mask: number; // 1 — бит проверяется, 0 — его значение не важно
}

export function boardStateFromTest(test: RunTest): BoardState {
  return {
    din: parseHex(test.din),
    dout: parseHex(test.dout),
    expected: parseHex(test.expected_dout),
    mask: parseHex(test.mask),
  };
}

// Бит не совпал, если он проверяется и получено не то, что ожидалось.
// ^ (XOR) даёт 1 там, где биты разные, & mask оставляет только проверяемые
export function isLedMismatch(state: BoardState, led: LedPin): boolean {
  return isBitSet((state.dout ^ state.expected) & state.mask, led.bit);
}

// Имена несовпавших светодиодов, например ['LEDR0', 'LEDG7']
export function mismatchedLeds(state: BoardState): string[] {
  return leds.filter((led) => isLedMismatch(state, led)).map((led) => led.name);
}
