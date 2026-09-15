# NCS 电动汽车充电桩数据分析可视化大屏

基于 Hadoop + Hive + Spark + Flask + Vue3 + DataV + ECharts 的大数据分析与可视化项目。

## 项目架构

```
3份CSV → HDFS → Hive(ODS/DWD/DWS/ADS) → MySQL → Flask API → Vue3大屏
```

## 环境要求

### 虚拟机（Linux）
- VMware 虚拟机，IP 需与后端配置一致（默认 192.168.176.100）
- 已安装：Hadoop 3.3.0、Hive 2.1.1、Spark 3.4.1、MySQL 5.7+
- MySQL 账号：root / 123456（如不同请修改 backend/app.py）

### 本地（Windows）
- Python 3.11 或 3.12
- Node.js 23+（推荐 24.x）
- 浏览器（Chrome/Edge）

---

## 第一步：数据准备（必须先做）

大屏数据存在虚拟机的 MySQL `ncs_ads` 库里。如果你的虚拟机还没有这些数据，需要先执行 ETL。

### 1.1 确认是否已有数据

在虚拟机里执行：

```bash
mysql -uroot -p123456 -e "USE ncs_ads; SHOW TABLES; SELECT COUNT(*) AS kpi_rows FROM ads_kpi_overview;"
```

- 如果看到 **11张表** 且 `kpi_rows = 1`，说明数据已就绪，**跳过 1.2，直接看第二步**。
- 如果库不存在或表为空，继续看 1.2。

### 1.2 执行一键 ETL（约5-10分钟）

前置条件：
- 3份原始CSV文件（nvv2t.csv、dsv13r2.csv、nvv2t_md_end.csv）已放在项目 `data/` 目录
- Hadoop、Hive、Spark 已启动

执行：

```bash
# 把整个项目传到虚拟机（用Xftp或scp），然后进入项目目录
cd /home/hadoop/ncs-dashboard

# 执行一键ETL
bash run.sh
```

`run.sh` 会自动完成以下7步：
1. 环境检查（Hadoop/Spark/MySQL是否启动）
2. 上传3份CSV到HDFS `/ncs/ods/`
3. ODS层建表（Hive外部表，3张）
4. DWD层清洗（三表LEFT JOIN，3340行明细）
5. DWS层聚合（7张汇总表）
6. ADS层指标（11张大屏指标表）
7. 导出到MySQL `ncs_ads` 库

执行完成后，重复 1.1 的命令确认数据已写入MySQL。

---

## 第二步：启动后端（Flask）

打开命令行窗口1：

```bash
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

看到 `Running on http://127.0.0.1:5000` 即启动成功。

**验证**：浏览器打开 http://127.0.0.1:5000/api/kpi，应返回类似：
```json
{"code":0,"data":{"sessions":3340,"total_kwh":19723.69,...},"msg":"success"}
```

> 如果连不上数据库，检查 `backend/app.py` 里的 `DB_CONFIG`，确认 host/user/password 与你的虚拟机一致。

---

## 第三步：启动前端（Vue3）

打开命令行窗口2（**不要关后端窗口**）：

```bash
cd frontend
npm install
npm run dev
```

看到 `Local: http://localhost:5173/` 即启动成功。

> 如果提示 5173 端口被占用，Vite 会自动换到 5174，访问提示的端口即可。

---

## 第四步：打开大屏

浏览器访问：**http://localhost:5173/**

应看到：顶部5个KPI卡片 + 三列8个图表（环形图、柱+折线混合图、堆叠柱状图、横向柱状图、分组柱状图）。

---

## 项目结构

```
ncs-dashboard/
├── backend/                    # Flask后端
│   ├── app.py                 # 主程序（13个API接口）
│   └── requirements.txt       # Python依赖
├── frontend/                   # Vue3前端
│   └── src/
│       ├── App.vue            # 大屏主组件（布局+8图表）
│       ├── api/index.js       # API请求封装
│       ├── main.js            # 入口（注册DataV）
│       └── style.css          # 全局样式
├── data/                       # 原始CSV数据
│   ├── nvv2t.csv             # 充电订单
│   ├── dsv13r2.csv           # BMS充电过程
│   └── nvv2t_md_end.csv      # 站点元数据
├── etl/
│   ├── sql/                   # 数仓SQL（ODS/DWD/DWS/ADS）
│   └── shell/04_export_ads_mysql.sh  # 导出MySQL脚本
├── docs/api.md                  # 后端13个接口完整文档
├── run.sh                      # 一键ETL脚本（7步）
└── README.md
```

---

## 常见问题

**Q: 前端页面空白，图表没数据？**
A: 按F12看控制台。常见原因：
- 后端没启动 → 确认 `python app.py` 在运行
- 虚拟机没开 → 启动虚拟机，确认MySQL可连
- 数据库没数据 → 回到第一步跑 `bash run.sh`

---

## 技术栈

- **大数据**：Hadoop 3.3.0 / HDFS / Hive 2.1.1 / Spark 3.4.1 (Spark SQL)
- **数据库**：MySQL 5.7
- **后端**：Python 3.12 / Flask 3.0 / PyMySQL
- **前端**：Vue3 / Vite / DataV (@kjgl77/datav-vue3) / ECharts 5 / Axios
