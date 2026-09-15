#!/usr/bin/env bash
# =====================================================================
# NCS 项目  01_etl_dwd.sh
# 作用：用 spark-sql 执行 DWD 明细层清洗（正式版，替代 hive 方式）
# 用法：sh 01_etl_dwd.sh
# 要点：本项目 ETL 统一采用 spark-sql 命令封装到 shell 脚本执行
#       （即 Hive on Spark：HQL 语法 + Spark 执行引擎）
#mkdir /home/hadoop/ncs_data/spark_sql
# =====================================================================
set -euo pipefail

# ---- 路径变量（按虚拟机实际目录调整）----
APP_HOME=/home/hadoop/ncs_data
SQL_DIR=${APP_HOME}/spark_sql
LOG_DIR=${APP_HOME}/logs
mkdir -p "${LOG_DIR}"

SCRIPT_NAME=$(basename "$0")
LOG_FILE=${LOG_DIR}/etl_dwd_$(date +%Y%m%d).log

log() { echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}"; }

log "================ DWD 明细层 ETL 开始 ================"

# 1) 进程前置检查：Spark 必须可用
if ! jps | grep -q Master; then
  log "[ERROR] 未检测到 Spark Master，请先执行 00_start_spark.sh"
  exit 1
fi

# 2) 调用 spark-sql 执行 SQL 文件
#    --conf 设定 shuffle 分区数，避免小数据产生过多任务
log "执行 SQL：01_dwd_charge_detail.sql"
spark-sql \
  --conf spark.sql.shuffle.partitions=20 \
  --conf spark.sql.parquet.compression.codec=snappy \
  -f "${SQL_DIR}/01_dwd_charge_detail.sql" 2>&1 | tee -a "${LOG_FILE}"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  log "DWD 明细层 ETL 执行成功。"
else
  log "[ERROR] DWD ETL 执行失败，请查看日志：${LOG_FILE}"
  exit 1
fi
log "================ DWD 明细层 ETL 结束 ================"
