import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    vueDevTools(),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    },
  },
  server: {
    host: true, // This is needed to accept connections from outside the container
    proxy: {
      // Any request starting with /users, /token, /links, etc.
      '/users': 'http://gateway:80',
      '/token': 'http://gateway:80',
      '/links': 'http://gateway:80',
      '/r': 'http://gateway:80',
    }
  }
})
