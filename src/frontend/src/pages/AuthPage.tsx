import React from 'react';
import {
  Card,
  CardHeader,
  Title2,
  Button,
  makeStyles,
  tokens,
} from '@fluentui/react-components';
import { Shield24Regular } from '@fluentui/react-icons';

const useStyles = makeStyles({
  pageLayout: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    width: '100vw',
    height: '100vh',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  card: {
    width: '360px',
    padding: '24px',
    backgroundColor: tokens.colorNeutralBackground1,
    boxShadow: tokens.shadow16,
    borderRadius: tokens.borderRadiusXLarge,
    display: 'flex',
    flexDirection: 'column',
    gap: '20px',
  },
  tpuButton: {
    backgroundColor: tokens.colorBrandBackground,
    color: '#FFFFFF',
    ':hover': {
      backgroundColor: tokens.colorBrandBackgroundHover,
      color: '#FFFFFF',
    },
    ':hover:active': {
      backgroundColor: tokens.colorBrandBackgroundPressed,
      color: '#FFFFFF',
    },
  },
});

interface AuthPageProps {
  onLogin: () => void;
}

export const AuthPage: React.FC<AuthPageProps> = ({ onLogin }) => {
  const styles = useStyles();

  return (
    <main className={styles.pageLayout}>
      <Card className={styles.card}>
        <CardHeader
          header={
            <Title2 block align="center">
              FPGA Remote Lab
            </Title2>
          }
        />
        
        <Button
          icon={<Shield24Regular />}
          size="large"
          className={styles.tpuButton}
          onClick={onLogin}
        >
          Войти с помощью TPU ID
        </Button>
      </Card>
    </main>
  );
};