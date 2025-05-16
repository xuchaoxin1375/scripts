// 兼容浏览器直接引入的方式
import App from './app.jsx';
import React from 'react';
import { createRoot } from 'react-dom/client';

const rootEl = document.getElementById('root');
if (rootEl) {
  createRoot(rootEl).render(<App />);
}
