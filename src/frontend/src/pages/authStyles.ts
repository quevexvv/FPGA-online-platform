import { makeStyles, tokens } from '@fluentui/react-components';

export const useAuthStyles = makeStyles({
  pageLayout: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    width: '100%',
    height: '100vh',
    boxSizing: 'border-box',
    padding: '16px',
    overflowY: 'auto',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  card: {
    width: '100%',
    maxWidth: '360px',
    boxSizing: 'border-box',
    flexShrink: 0,
    marginTop: 'auto',
    marginBottom: 'auto',
    padding: '24px',
    backgroundColor: tokens.colorNeutralBackground1,
    boxShadow: tokens.shadow16,
    borderRadius: tokens.borderRadiusXLarge,
  },
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
  },
  error: {
    color: tokens.colorPaletteRedForeground1,
  },
  footer: {
    textAlign: 'center',
    margin: 0,
    color: tokens.colorNeutralForeground2,
  },
  link: {
    color: tokens.colorBrandForegroundLink,
    fontWeight: tokens.fontWeightSemibold,
    textDecorationLine: 'none',
    ':hover': {
      textDecorationLine: 'underline',
    },
  },
  themeToolbar: {
    width: '100%',
    display: 'flex',
    justifyContent: 'flex-end',
    flexShrink: 0,
  },
});
