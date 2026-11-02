import { webLightTheme, webDarkTheme, Theme } from '@fluentui/react-components';
import { lightPalette, darkPalette } from './colors';

export const customLightTheme: Theme = {
  ...webLightTheme,
  colorNeutralBackground1: lightPalette.bgPanel,
  colorNeutralBackground2: lightPalette.bgWindow,
  colorNeutralForeground1: lightPalette.textMain,
  colorNeutralForeground2: lightPalette.textMuted,
  colorBrandBackground: lightPalette.primaryGreen,
  colorBrandBackgroundHover: lightPalette.primaryGreenHover,
  colorBrandBackgroundPressed: lightPalette.primaryGreenPressed,
};

export const customDarkTheme: Theme = {
  ...webDarkTheme,
  colorNeutralBackground1: darkPalette.bgPanel,
  colorNeutralBackground2: darkPalette.bgWindow,
  colorNeutralForeground1: darkPalette.textMain,
  colorNeutralForeground2: darkPalette.textMuted,
  colorBrandBackground: darkPalette.primaryGreen,
  colorBrandBackgroundHover: darkPalette.primaryGreenHover,
  colorBrandBackgroundPressed: darkPalette.primaryGreenPressed,
};