import React from 'react';
import { makeStyles, tokens } from '@fluentui/react-components';

const useStyles = makeStyles({
  page: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    height: '100%',
    color: tokens.colorNeutralForeground2,
    fontSize: '18px',
  },
});

interface EmptyPageProps {
  title: string;
}

export const EmptyPage: React.FC<EmptyPageProps> = ({ title }) => {
  const styles = useStyles();

  return <div className={styles.page}>{title} (пусто)</div>;
};
