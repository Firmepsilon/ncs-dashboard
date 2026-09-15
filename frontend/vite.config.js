import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    host: '0.0.0.0', // 允许局域网/远程浏览器访问
    port: 5173,
    proxy: {
      // 前端用相对路径 /api，由 vite 转发给 Flask，避免浏览器直连 127.0.0.1
      '/api': {
        target: 'http://127.0.0.1:5000',
        changeOrigin: true,
      },
    },
  },
})