import React from 'react';
import { useParams } from 'react-router';
import { EmptyPage } from '../components/EmptyPage';
import { mockLabs } from '../mockLabs';

export const LabTaskPage: React.FC = () => {
  // id работы берётся из адреса: /labs/:labId
  const { labId } = useParams();
  const lab = mockLabs.find((item) => item.id === labId);

  return <EmptyPage title={lab ? `Задание: ${lab.title}` : 'Лабораторная не найдена'} />;
};