import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  // Relative URLs support /repo/, account Pages sites, and custom domains.
  base: './',
  plugins: [react(), {
    name: 'bundle-demo-video',
    // Vite serves the MP4 from the project root in dev. Ship the same file in dist.
    closeBundle() {
      copyFileSync(fileURLToPath(new URL('./tapcpeso-demo.mp4', import.meta.url)),
        fileURLToPath(new URL('./dist/tapcpeso-demo.mp4', import.meta.url)));
    },
  }],
  build: { outDir: 'dist', emptyOutDir: true },
});
