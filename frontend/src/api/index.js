// API 请求封装
import axios from 'axios'

const request = axios.create({
  baseURL: '/api',
  timeout: 10000,
})

// 响应拦截：统一取 data 字段
request.interceptors.response.use(
  (res) => {
    if (res.data.code === 0) {
      return res.data.data
    }
    return Promise.reject(new Error(res.data.msg || '请求失败'))
  },
  (err) => Promise.reject(err)
)

// ========== 接口列表 ==========

// 探活
export const getHealth = () => request.get('/health')

// 顶部 KPI
export const getKpi = () => request.get('/kpi')

// 平台分布
export const getPlatform = () => request.get('/platform')

// 24小时趋势
export const getHourTrend = () => request.get('/hour-trend')

// 桩型偏好
export const getStationType = () => request.get('/station-type')

// TOP10站点
export const getStationTop10 = () => request.get('/station-top10')

// SOC雷达
export const getSocRadar = () => request.get('/soc-radar')

// 小时×区域堆叠
export const getHourArea = () => request.get('/hour-area')

// 区域KPI
export const getAreaKpi = () => request.get('/area-kpi')

// 用户分级
export const getUserLevel = () => request.get('/user-level')

// 工作日vs周末
export const getWeekCompare = () => request.get('/week-compare')

// 电池健康
export const getBatteryHealth = () => request.get('/battery-health')

// 用户雷达
export const getUserRadar = () => request.get('/user-radar')
