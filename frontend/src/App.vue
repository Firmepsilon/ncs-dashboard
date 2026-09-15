<template>
  <div class="full-screen">
    <div class="dashboard">
      <!-- 顶部标题栏 -->
      <header class="header">
        <div class="header-left"></div>
        <h1 class="title">
          <span class="deco"></span>
          电动汽车充电桩数据分析可视化大屏
          <span class="deco"></span>
        </h1>
        <div class="header-right">{{ currentTime }}</div>
      </header>

      <!-- KPI 卡片行 -->
      <section class="kpi-row">
        <div v-for="(item, idx) in kpiList" :key="idx" class="kpi-card">
          <dv-border-box-8 :color="['#00deff', '#0066ff']" class="kpi-border">
            <div class="kpi-label">{{ item.label }}</div>
            <div class="kpi-value" :style="{ color: item.color }">
              <span class="kpi-number">{{ item.value.toLocaleString() }}</span>
              <span class="kpi-unit">{{ item.unit }}</span>
            </div>
          </dv-border-box-8>
        </div>
      </section>

      <!-- 主体三列 -->
      <main class="main">
        <!-- 左列 -->
        <div class="col">
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box">
            <div class="chart-title">用户平台偏好分布</div>
            <div ref="platformChart" class="chart"></div>
          </dv-border-box-11>
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box">
            <div class="chart-title">用户等级分布</div>
            <div ref="userLevelChart" class="chart"></div>
          </dv-border-box-11>
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box">
            <div class="chart-title">电池健康(SOC档位)占比</div>
            <div ref="batteryChart" class="chart"></div>
          </dv-border-box-11>
        </div>

        <!-- 中列 -->
        <div class="col col-center">
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box chart-tall">
            <div class="chart-title">各时段充电趋势</div>
            <div ref="hourTrendChart" class="chart"></div>
          </dv-border-box-11>
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box chart-tall">
            <div class="chart-title">24小时各区域充电分布</div>
            <div ref="hourAreaChart" class="chart"></div>
          </dv-border-box-11>
        </div>

        <!-- 右列 -->
        <div class="col">
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box">
            <div class="chart-title">充电站类型偏好</div>
            <div ref="stationTypeChart" class="chart"></div>
          </dv-border-box-11>
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box">
            <div class="chart-title">工作日 vs 周末对比</div>
            <div ref="weekCompareChart" class="chart"></div>
          </dv-border-box-11>
          <dv-border-box-11 :color="['#00deff', '#0066ff']" class="chart-box">
            <div class="chart-title">运营效率 TOP10 充电站</div>
            <div ref="stationTop10Chart" class="chart"></div>
          </dv-border-box-11>
        </div>
      </main>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import * as echarts from 'echarts'
import {
  getKpi, getPlatform, getUserLevel, getBatteryHealth,
  getHourTrend, getHourArea, getStationType, getWeekCompare, getStationTop10
} from './api'

// 当前时间
const currentTime = ref('')
let timeTimer = null
const updateTime = () => {
  const now = new Date()
  currentTime.value = now.toLocaleString('zh-CN', { hour12: false })
}

// KPI 数据
const kpiList = ref([
  { label: '累计充电次数', value: 0, unit: '次', color: '#00deff' },
  { label: '累计充电量', value: 0, unit: '度', color: '#00ff88' },
  { label: '累计营收', value: 0, unit: '元', color: '#ffcc00' },
  { label: '充电站总数', value: 0, unit: '个', color: '#ff6600' },
  { label: 'BMS明细缺失率', value: 0, unit: '%', color: '#ff4466' },
])

// 图表 ref
const platformChart = ref(null)
const userLevelChart = ref(null)
const batteryChart = ref(null)
const hourTrendChart = ref(null)
const hourAreaChart = ref(null)
const stationTypeChart = ref(null)
const weekCompareChart = ref(null)
const stationTop10Chart = ref(null)

let charts = []

// 通用饼图配置
const pieOption = (data, title, colors) => ({
  tooltip: { trigger: 'item', formatter: '{b}: {c} ({d}%)' },
  legend: { bottom: '3%', textStyle: { color: '#aaa', fontSize: 11 }, itemWidth: 12, itemHeight: 12 },
  color: colors || ['#00deff', '#00ff88', '#ffcc00', '#ff6600', '#ff4466', '#aa66ff'],
  series: [{
    name: title,
    type: 'pie',
    radius: ['42%', '68%'],
    center: ['50%', '44%'],
    avoidLabelOverlap: true,
    itemStyle: { borderRadius: 6, borderColor: '#0a0e27', borderWidth: 2 },
    label: { show: false },
    emphasis: { label: { show: true, fontSize: 14, fontWeight: 'bold', color: '#fff' } },
    data: data,
  }],
})

// 加载所有数据
const loadData = async () => {
  try {
    // KPI
    const kpi = await getKpi()
    kpiList.value[0].value = kpi.sessions || 0
    kpiList.value[1].value = kpi.total_kwh || 0
    kpiList.value[2].value = kpi.total_fee || 0
    kpiList.value[3].value = kpi.station_count || 0
    kpiList.value[4].value = kpi.abnormal_rate || 0

    // 平台分布
    const platform = await getPlatform()
    charts[0].setOption(pieOption(
      platform.map(d => ({ name: d.phone_type, value: d.user_count })),
      '平台分布'
    ))

    // 用户等级
    const userLevel = await getUserLevel()
    charts[1].setOption(pieOption(
      userLevel.map(d => ({ name: d.user_level, value: d.user_count })),
      '用户等级'
    ))

    // 电池健康
    const battery = await getBatteryHealth()
    charts[2].setOption(pieOption(
      battery.map(d => ({ name: d.health_level, value: d.sess_count })),
      '电池健康',
      ['#ff4466', '#ff9900', '#00ff88', '#00deff']
    ))

    // 24小时趋势（柱+折线）
    const hourTrend = await getHourTrend()
    charts[3].setOption({
      tooltip: { trigger: 'axis' },
      legend: { data: ['充电次数', '充电量(度)'], textStyle: { color: '#aaa' }, top: 5 },
      grid: { left: '8%', right: '8%', bottom: '12%', top: '20%' },
      xAxis: { type: 'category', data: hourTrend.map(d => d.hour + '时'), axisLine: { lineStyle: { color: '#333' } }, axisLabel: { color: '#888', fontSize: 10 } },
      yAxis: [
        { type: 'value', name: '次数', axisLine: { show: false }, splitLine: { lineStyle: { color: 'rgba(255,255,255,0.05)' } }, axisLabel: { color: '#888' } },
        { type: 'value', name: '电量', axisLine: { show: false }, splitLine: { show: false }, axisLabel: { color: '#888' } },
      ],
      series: [
        { name: '充电次数', type: 'bar', data: hourTrend.map(d => d.sessions), itemStyle: { color: new echarts.graphic.LinearGradient(0,0,0,1,[{offset:0,color:'#00deff'},{offset:1,color:'#0066ff'}]), borderRadius: [4,4,0,0] }, barWidth: '40%' },
        { name: '充电量(度)', type: 'line', yAxisIndex: 1, data: hourTrend.map(d => d.total_kwh), smooth: true, itemStyle: { color: '#ffcc00' }, lineStyle: { width: 2 }, areaStyle: { color: new echarts.graphic.LinearGradient(0,0,0,1,[{offset:0,color:'rgba(255,204,0,0.3)'},{offset:1,color:'rgba(255,204,0,0)'}]) } },
      ],
    })

    // 小时×区域堆叠
    const hourArea = await getHourArea()
    const areas = [...new Set(hourArea.map(d => d.station_area))]
    const hours = [...new Set(hourArea.map(d => d.hour))].sort((a,b) => a-b)
    const areaColors = ['#00deff','#00ff88','#ffcc00','#ff6600','#ff4466','#aa66ff','#66ccff','#ff99cc']
    charts[4].setOption({
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      legend: { data: areas, textStyle: { color: '#aaa', fontSize: 10 }, top: 5, type: 'scroll' },
      grid: { left: '8%', right: '5%', bottom: '12%', top: '22%' },
      xAxis: { type: 'category', data: hours.map(h => h+'时'), axisLabel: { color: '#888', fontSize: 10 } },
      yAxis: { type: 'value', axisLine: { show: false }, splitLine: { lineStyle: { color: 'rgba(255,255,255,0.05)' } }, axisLabel: { color: '#888' } },
      series: areas.map((area, i) => ({
        name: area, type: 'bar', stack: 'total', barWidth: '50%',
        itemStyle: { color: areaColors[i % areaColors.length] },
        data: hours.map(h => {
          const found = hourArea.find(d => d.hour === h && d.station_area === area)
          return found ? found.sessions : 0
        }),
      })),
    })

    // 桩型偏好
    const stationType = await getStationType()
    charts[5].setOption(pieOption(
      stationType.map(d => ({ name: d.gun_type, value: d.utilization_rate })),
      '桩型偏好'
    ))

    // 工作日vs周末
    const weekCompare = await getWeekCompare()
    charts[6].setOption({
      tooltip: { trigger: 'axis' },
      legend: { data: ['充电次数', '充电量'], textStyle: { color: '#aaa' }, top: 5 },
      grid: { left: '15%', right: '10%', bottom: '15%', top: '25%' },
      xAxis: { type: 'category', data: weekCompare.map(d => d.day_type), axisLabel: { color: '#aaa' } },
      yAxis: { type: 'value', axisLine: { show: false }, splitLine: { lineStyle: { color: 'rgba(255,255,255,0.05)' } }, axisLabel: { color: '#888' } },
      series: [
        { name: '充电次数', type: 'bar', data: weekCompare.map(d => d.sessions), itemStyle: { color: '#00deff', borderRadius: [4,4,0,0] }, barWidth: '30%' },
        { name: '充电量', type: 'bar', data: weekCompare.map(d => d.total_kwh), itemStyle: { color: '#ffcc00', borderRadius: [4,4,0,0] }, barWidth: '30%' },
      ],
    })

    // TOP10站点横向柱状
    const top10 = await getStationTop10()
    const top10Sorted = [...top10].sort((a,b) => a.total_sessions - b.total_sessions)
    charts[7].setOption({
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, formatter: function(params) {
        const idx = params[0].dataIndex
        return top10Sorted[idx].station_name + '<br/>充电次数: ' + top10Sorted[idx].total_sessions
      }},
      grid: { left: '42%', right: '12%', bottom: '5%', top: '5%' },
      xAxis: { type: 'value', axisLine: { show: false }, splitLine: { lineStyle: { color: 'rgba(255,255,255,0.05)' } }, axisLabel: { color: '#888' } },
      yAxis: { type: 'category', data: top10Sorted.map(d => d.station_name), axisLabel: { color: '#aaa', fontSize: 10, width: 120, overflow: 'truncate' } },
      series: [{
        type: 'bar',
        data: top10Sorted.map(d => d.total_sessions),
        barWidth: '55%',
        itemStyle: {
          color: new echarts.graphic.LinearGradient(0,0,1,0,[{offset:0,color:'#0066ff'},{offset:1,color:'#00deff'}]),
          borderRadius: [0,4,4,0],
        },
        label: { show: true, position: 'right', color: '#00deff', fontSize: 11 },
      }],
    })

  } catch (err) {
    console.error('数据加载失败:', err)
  }
}

onMounted(() => {
  updateTime()
  timeTimer = setInterval(updateTime, 1000)

  // 先加载数据（确保一定执行）
  loadData()

  // 初始化图表
  try {
    const chartRefs = [platformChart, userLevelChart, batteryChart, hourTrendChart, hourAreaChart, stationTypeChart, weekCompareChart, stationTop10Chart]
    charts = chartRefs.map(ref => echarts.init(ref.value))
  } catch (e) {
    console.error('图表初始化失败:', e)
  }

  // 窗口 resize
  const handleResize = () => charts.forEach(c => c && c.resize())
  window.addEventListener('resize', handleResize)
  onUnmounted(() => {
    clearInterval(timeTimer)
    window.removeEventListener('resize', handleResize)
    charts.forEach(c => c && c.dispose())
  })
})
</script>

<style scoped>
.full-screen {
  width: 100%;
  height: 100%;
  overflow: hidden;
}
.dashboard {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 10px 20px;
}

/* 顶部 */
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 60px;
  flex-shrink: 0;
}
.header-left, .header-right {
  width: 200px;
  color: #00deff;
  font-size: 14px;
}
.header-right {
  text-align: right;
}
.title {
  font-size: 26px;
  font-weight: bold;
  color: #fff;
  text-shadow: 0 0 20px rgba(0,222,255,0.5);
  display: flex;
  align-items: center;
  gap: 15px;
  letter-spacing: 4px;
}
.deco {
  width: 120px;
  height: 3px;
  background: linear-gradient(90deg, transparent, #00deff, #0066ff, transparent);
  border-radius: 2px;
}

/* KPI 行 */
.kpi-row {
  display: flex;
  gap: 15px;
  margin: 10px 0;
  flex-shrink: 0;
}
.kpi-card {
  flex: 1;
  height: 90px;
}
.kpi-border {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.kpi-label {
  font-size: 13px;
  color: #888;
  margin-bottom: 6px;
}
.kpi-value {
  display: flex;
  align-items: baseline;
  gap: 4px;
}
.kpi-number {
  font-size: 32px;
  font-weight: bold;
  font-family: 'Arial', sans-serif;
  text-shadow: 0 0 12px currentColor;
}
.kpi-unit {
  font-size: 13px;
  color: #888;
}

/* 主体三列 */
.main {
  flex: 1;
  display: flex;
  gap: 15px;
  min-height: 0;
}
.col {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 15px;
  min-height: 0;
}
.col-center {
  flex: 1.3;
}

/* 图表盒子 */
.chart-box {
  flex: 1;
  min-height: 0;
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 10px 14px;
}
.chart-tall {
  flex: 1.2;
}
.chart-title {
  font-size: 15px;
  color: #00deff;
  font-weight: bold;
  margin-bottom: 8px;
  padding-bottom: 6px;
  border-bottom: 1px solid rgba(0, 222, 255, 0.2);
  flex-shrink: 0;
  letter-spacing: 1px;
}
.chart {
  flex: 1;
  min-height: 150px;
  width: 100%;
}
</style>
