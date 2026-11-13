import React, { useState } from 'react';
import {
  Button,
  makeStyles,
  mergeClasses,
  Spinner,
  Tab,
  TabList,
  tokens,
} from '@fluentui/react-components';
import { Link, useParams } from 'react-router';
import { useLab } from '@/hooks/useLab';
import { CodeEditor } from '@/components/workspace/CodeEditor';
import { LabDetail } from '@/types';
import boardImage from '@/assets/fpga-board.svg';

const useStyles = makeStyles({
  // Две колонки: слева редактор, справа плата и проверка
  page: {
    height: '100%',
    boxSizing: 'border-box',
    padding: '24px 32px',
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)',
    gap: '24px',
    backgroundColor: tokens.colorNeutralBackground2,
  },
  card: {
    backgroundColor: tokens.colorNeutralBackground1,
    borderRadius: tokens.borderRadiusXLarge,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    boxSizing: 'border-box',
    // Без minHeight: 0 содержимое растянуло бы карточку выше экрана вместо прокрутки
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  rightColumn: {
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
    gap: '24px',
  },
  boardCard: {
    flexShrink: 0,
    padding: '16px',
    alignItems: 'center',
  },
  boardImage: {
    display: 'block',
    width: '100%',
    // Плата уменьшается вместе с окном, но не растягивается выше 360px
    maxHeight: '360px',
    objectFit: 'contain',
  },
  checkCard: {
    flex: 1,
    padding: '20px 24px',
  },
  tabs: {
    flexShrink: 0,
    padding: '4px 12px 0',
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  editorWrapper: {
    flex: 1,
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
  },
  hidden: {
    display: 'none',
  },
  // Вкладка с заданием: условие и интерфейс прокручиваются, если не помещаются
  taskText: {
    flex: 1,
    minHeight: 0,
    overflowY: 'auto',
    padding: '8px 24px 24px',
  },
  sectionTitle: {
    margin: '16px 0 8px',
    fontSize: '15px',
    fontWeight: '600',
    color: tokens.colorNeutralForeground1,
  },
  text: {
    margin: 0,
    fontSize: '14px',
    lineHeight: '1.6',
    color: tokens.colorNeutralForeground1,
    whiteSpace: 'pre-wrap',
  },
  placeholder: {
    flex: 1,
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    padding: '24px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
  },
  // Сообщение на всю страницу: загрузка, ошибка, лабораторная не выбрана
  stateMessage: {
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    alignItems: 'center',
    gap: '12px',
    fontSize: '14px',
    color: tokens.colorNeutralForeground2,
    backgroundColor: tokens.colorNeutralBackground2,
  },
  link: {
    color: tokens.colorBrandForeground1,
    fontWeight: '600',
    textDecoration: 'none',
  },
});

type EditorTab = 'code' | 'task';

// Рабочее пространство для уже загруженной лабораторной
const WorkspaceContent: React.FC<{ lab: LabDetail }> = ({ lab }) => {
  const styles = useStyles();
  const [tab, setTab] = useState<EditorTab>('code');

  return (
    <div className={styles.page}>
      {/* Левая колонка: код и задание во вкладках */}
      <section className={styles.card} aria-label="Редактор кода">
        <TabList
          className={styles.tabs}
          selectedValue={tab}
          onTabSelect={(_, data) => setTab(data.value as EditorTab)}
        >
          <Tab value="code">student_top.v</Tab>
          <Tab value="task">Задание</Tab>
        </TabList>

        {/* Редактор только прячем, а не убираем: так не теряются курсор и история отмены */}
        <div className={tab === 'code' ? styles.editorWrapper : styles.hidden}>
          <CodeEditor
            initialValue={lab.template}
            // Текст решения понадобится для отправки, её добавим в следующем коммите
            onChange={() => {}}
            ariaLabel="Код решения на Verilog"
          />
        </div>

        {tab === 'task' && (
          <div className={styles.taskText}>
            <h2 className={styles.sectionTitle}>{lab.title}</h2>
            <p className={styles.text}>{lab.statement}</p>
            <h2 className={styles.sectionTitle}>Интерфейс модуля</h2>
            <p className={styles.text}>{lab.interface_description}</p>
          </div>
        )}
      </section>

      {/* Правая колонка: плата и проверка */}
      <div className={styles.rightColumn}>
        <section className={mergeClasses(styles.card, styles.boardCard)} aria-label="Плата">
          <img className={styles.boardImage} src={boardImage} alt="Отладочная плата с ПЛИС" />
        </section>

        <section
          className={mergeClasses(styles.card, styles.checkCard)}
          aria-label="Проверка решения"
        >
          <div className={styles.placeholder}>Здесь будут отправка и ход проверки</div>
        </section>
      </div>
    </div>
  );
};

export const WorkspacePage: React.FC = () => {
  const styles = useStyles();
  // id лабораторной берётся из адреса: /workspace/:labId
  const { labId } = useParams();
  const { lab, error, isNotFound, retry } = useLab(labId);

  // Рабочее пространство открыли из шапки, без выбранной лабораторной
  if (!labId) {
    return (
      <div className={styles.stateMessage}>
        Выберите лабораторную, чтобы начать работу
        <Link to="/labs" className={styles.link}>
          К списку лабораторных
        </Link>
      </div>
    );
  }

  if (isNotFound) {
    return <div className={styles.stateMessage}>Лабораторная не найдена</div>;
  }

  if (error) {
    return (
      <div className={styles.stateMessage} role="alert">
        {error}
        <Button onClick={retry}>Повторить</Button>
      </div>
    );
  }

  if (lab === null) {
    return (
      <div className={styles.stateMessage}>
        <Spinner label="Загружаем задание..." />
      </div>
    );
  }

  // key: при переходе к другой лабораторной содержимое создаётся заново с её шаблоном
  return <WorkspaceContent key={lab.id} lab={lab} />;
};
