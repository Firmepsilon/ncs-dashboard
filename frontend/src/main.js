import { createApp } from 'vue'
import './style.css'
import App from './App.vue'

// 注册 DataV 大屏组件
import DataVVue3 from '@kjgl77/datav-vue3'

const app = createApp(App)
app.use(DataVVue3)
app.mount('#app')
