import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  // BrowserRouter следит за адресом в браузере и сообщает его приложению
  <BrowserRouter>
    <App />
  </BrowserRouter>
);