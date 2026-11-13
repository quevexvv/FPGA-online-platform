import React, { useEffect, useRef } from 'react';
import { makeStyles, tokens } from '@fluentui/react-components';
import { basicSetup } from 'codemirror';
import { indentWithTab } from '@codemirror/commands';
import {
  HighlightStyle,
  indentUnit,
  StreamLanguage,
  syntaxHighlighting,
} from '@codemirror/language';
import { verilog } from '@codemirror/legacy-modes/mode/verilog';
import { EditorState } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { tags } from '@lezer/highlight';

// Цвета подсветки Verilog. Токены Fluent — это CSS-переменные,
// поэтому цвета сами меняются при переключении светлой и тёмной темы
const verilogHighlight = HighlightStyle.define([
  { tag: tags.keyword, color: tokens.colorPaletteBlueForeground2 },
  { tag: tags.number, color: tokens.colorPaletteDarkOrangeForeground1 },
  { tag: tags.string, color: tokens.colorPaletteBerryForeground1 },
  { tag: tags.comment, color: tokens.colorNeutralForeground3, fontStyle: 'italic' },
  // Директивы вроде `timescale
  { tag: tags.definition(tags.variableName), color: tokens.colorPaletteTealForeground2 },
]);

// Внешний вид редактора под тему Fluent
const editorTheme = EditorView.theme({
  '&': {
    height: '100%',
    fontSize: '13px',
    color: tokens.colorNeutralForeground1,
    backgroundColor: tokens.colorNeutralBackground1,
  },
  // Рамку фокуса рисует карточка вокруг редактора (см. стиль editor ниже)
  '&.cm-focused': { outline: 'none' },
  '.cm-scroller': { fontFamily: tokens.fontFamilyMonospace, lineHeight: '1.6' },
  '.cm-content': { padding: '12px 0', caretColor: tokens.colorNeutralForeground1 },
  '.cm-cursor': { borderLeftColor: tokens.colorNeutralForeground1 },
  '.cm-gutters': {
    color: tokens.colorNeutralForeground3,
    backgroundColor: tokens.colorNeutralBackground1,
    border: 'none',
  },
  '.cm-activeLine': { backgroundColor: tokens.colorSubtleBackgroundHover },
  '.cm-activeLineGutter': {
    color: tokens.colorNeutralForeground1,
    backgroundColor: 'transparent',
  },
  '&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground':
    { backgroundColor: tokens.colorBrandBackground2 },
});

const useStyles = makeStyles({
  editor: {
    flex: 1,
    minHeight: 0,
    // Клавиатурный фокус внутри редактора видно по зелёной линии сверху
    borderTop: '2px solid transparent',
    ':focus-within': { borderTopColor: tokens.colorBrandStroke1 },
  },
});

interface CodeEditorProps {
  initialValue: string; // текст при создании редактора
  onChange: (value: string) => void;
  ariaLabel: string;
}

// Редактор кода на CodeMirror 6 с подсветкой Verilog
export const CodeEditor: React.FC<CodeEditorProps> = ({ initialValue, onChange, ariaLabel }) => {
  const styles = useStyles();
  // div, внутрь которого CodeMirror нарисует редактор
  const containerRef = useRef<HTMLDivElement>(null);
  // Редактор создаётся один раз, а функцию onChange родитель может передавать новую
  // при каждой перерисовке. В ref всегда лежит последняя
  const onChangeRef = useRef(onChange);
  useEffect(() => {
    onChangeRef.current = onChange;
  });

  useEffect(() => {
    if (!containerRef.current) return;

    const view = new EditorView({
      parent: containerRef.current,
      state: EditorState.create({
        doc: initialValue,
        extensions: [
          // Номера строк, подсветка текущей строки, отмена, автоотступы и т. д.
          basicSetup,
          StreamLanguage.define(verilog),
          syntaxHighlighting(verilogHighlight),
          editorTheme,
          // Tab добавляет отступ. Чтобы уйти из редактора клавиатурой: Esc, затем Tab
          keymap.of([indentWithTab]),
          indentUnit.of('    '),
          EditorState.tabSize.of(4),
          EditorView.contentAttributes.of({ 'aria-label': ariaLabel }),
          // Сообщаем родителю о каждом изменении текста
          EditorView.updateListener.of((update) => {
            if (update.docChanged) onChangeRef.current(update.state.doc.toString());
          }),
        ],
      }),
    });

    // Уходим со страницы — убираем редактор
    return () => view.destroy();
  }, [initialValue, ariaLabel]);

  return <div ref={containerRef} className={styles.editor} />;
};
