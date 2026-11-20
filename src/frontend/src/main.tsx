import { StrictMode } from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import App from './App';
import { AuthProvider } from '@/auth/AuthContext';
import './index.css';

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  // StrictMode в режиме разработки нарочно запускает эффекты дважды,
  // чтобы сразу было видно эффекты без правильной очистки.
  // В сборке для сервера он ничего не делает
  <StrictMode>
    {/* BrowserRouter следит за адресом в браузере и сообщает его приложению */}
    <BrowserRouter>
      <AuthProvider>
        <App />
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
