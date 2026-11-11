import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    // Запросы на /api/... dev-сервер пересылает бэкенду и убирает префикс /api.
    // Для браузера сайт и API живут на одном адресе, поэтому cookie сессии работает без CORS
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        rewrite: (requestPath) => requestPath.replace(/^\/api/, ''),
      },
    },
  },
});