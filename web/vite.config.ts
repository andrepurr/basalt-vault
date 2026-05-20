import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5174,
    proxy: {
      '/rpc': {
        target: 'http://127.0.0.1:5175',
        rewrite: (path) => path.replace(/^\/rpc/, ''),
      },
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id: string) {
          if (id.includes('node_modules/katex')) return 'katex';
          if (id.includes('node_modules/motion') || id.includes('node_modules/framer-motion')) return 'motion';
          if (id.includes('node_modules/wagmi') || id.includes('node_modules/viem') || id.includes('node_modules/@wagmi')) return 'web3';
        },
      },
    },
  },
  css: {
    devSourcemap: true,
  },
});
