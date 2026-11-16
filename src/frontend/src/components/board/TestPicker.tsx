import React from 'react';
import { makeStyles, ToggleButton } from '@fluentui/react-components';
import { Checkmark12Filled, Dismiss12Filled } from '@fluentui/react-icons';
import { appTokens } from '@/theme/themes';
import { RunTest } from '@/types';

const useStyles = makeStyles({
  // Кнопки переносятся на новую строку, если тестов много
  list: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '8px',
  },
  passed: { color: appTokens.stepDone },
  failed: { color: appTokens.terminalError },
});

interface TestPickerProps {
  tests: RunTest[];
  selectedIndex: number;
  onSelect: (index: number) => void;
}

// Кнопки открытых тестов: какой выбран, тот и показываем на плате
export const TestPicker: React.FC<TestPickerProps> = ({ tests, selectedIndex, onSelect }) => {
  const styles = useStyles();

  return (
    <div className={styles.list} role="group" aria-label="Открытые тесты">
      {tests.map((test, index) => (
        <ToggleButton
          key={test.vector_index}
          size="small"
          checked={index === selectedIndex}
          onClick={() => onSelect(index)}
          icon={
            test.match ? (
              <Checkmark12Filled className={styles.passed} />
            ) : (
              <Dismiss12Filled className={styles.failed} />
            )
          }
          // Галочку и крестик скринридер не прочитает, поэтому говорим словами
          aria-label={`Тест ${test.vector_index + 1}, ${test.match ? 'пройден' : 'не пройден'}`}
        >
          Тест {test.vector_index + 1}
        </ToggleButton>
      ))}
    </div>
  );
};
