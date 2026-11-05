import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

// Milestone 1 replaces this with the application shell (src/app).
const root = document.getElementById('root');
if (!root) throw new Error('Missing #root element');
createRoot(root).render(
  <StrictMode>
    <main>Afterlight</main>
  </StrictMode>,
);
