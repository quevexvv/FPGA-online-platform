import { createDarkTheme, createLightTheme, Theme } from '@fluentui/react-components';
import { darkPalette, greenBrand, lightPalette } from './colors';

type Palette = typeof lightPalette;

// Общие настройки для обеих тем: подставляем цвета из дизайна в Figma в токены Fluent
const paletteTokens = (palette: Palette): Partial<Theme> => ({
  colorNeutralBackground1: palette.bgPanel,
  colorNeutralBackground2: palette.bgWindow,
  colorNeutralBackground3: palette.badgeNeutral,
  colorNeutralForeground1: palette.textMain,
  colorNeutralForeground2: palette.textSecondary,
  colorNeutralForeground3: palette.textAccent,
  colorNeutralForegroundDisabled: palette.textDisabled,
  colorNeutralStroke1: palette.strokeStrong,
  colorNeutralStroke2: palette.stroke,
  colorNeutralStroke3: palette.strokeSubtle,
  colorBrandBackground: palette.primaryGreen,
  colorBrandBackgroundHover: palette.primaryGreenHover,
  colorBrandBackgroundPressed: palette.primaryGreenPressed,
  colorBrandForeground1: palette.primaryGreen,
  colorStatusSuccessForeground1: palette.primaryGreen,
  colorStatusSuccessBackground1: palette.successBackground,
  colorStatusWarningForeground1: palette.warning,
  colorStatusWarningBackground1: palette.warningBackground,
});

// Свои токены приложения, которых нет во Fluent. FluentProvider превращает каждое поле темы
// в CSS-переменную (--terminalBackground и т. д.), поэтому они переключаются вместе с темой
const appTokenValues = (palette: Palette) => ({
  terminalBackground: palette.terminalBackground,
  terminalTitle: palette.terminalTitle,
  terminalInfo: palette.terminalInfo,
  terminalStatus: palette.terminalStatus,
  terminalError: palette.terminalError,
  stepDone: palette.stepDone,
  stepCurrent: palette.stepCurrent,
  stepPending: palette.stepPending,
  stepPendingText: palette.stepPendingText,
  stepLine: palette.stepLine,
});

// Ссылки на эти переменные для стилей, по аналогии с tokens из Fluent: appTokens.terminalInfo
export const appTokens = Object.fromEntries(
  Object.keys(appTokenValues(lightPalette)).map((name) => [name, `var(--${name})`]),
) as Record<keyof ReturnType<typeof appTokenValues>, string>;

export const customLightTheme: Theme = {
  ...createLightTheme(greenBrand),
  ...paletteTokens(lightPalette),
  ...appTokenValues(lightPalette),
};

export const customDarkTheme: Theme = {
  ...createDarkTheme(greenBrand),
  ...paletteTokens(darkPalette),
  ...appTokenValues(darkPalette),
};
