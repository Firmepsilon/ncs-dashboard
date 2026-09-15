-- =====================================================================
-- NCS 充电桩项目  DWD 明细层 —— 正式版（spark-sql 执行引擎）
-- 文件：01_dwd_charge_detail.sql
-- 说明：由第一天的 03_dwd_clean_demo.hql 重写而来，统一改用 spark-sql 执行，
--       表落地为 Parquet + Snappy。表名严格沿用第一天 01_ods_create.hql：
--         ncs_ods.ods_charging_order        （来源 nvv2t.csv，订单，3395 行）
--         ncs_ods.ods_charging_process      （来源 dsv13r2.csv，BMS 过程，1594 行）
--         ncs_ods.ods_charging_station_meta （来源 nvv2t_md_end.csv，站点元数据，105 站）
-- 关键事实（用真实数据核对过，避免“能跑但 0 行”）：
--   ① 关联键：order.sessionId = process.esd（仅 1594 个订单有 BMS 明细，故用 LEFT JOIN）
--             order.stationId = meta.stationId（105 个站点 100% 可关联）
--   ② order 的 created/ended 年份异常(0014/0015)，不可作为日期；process.record_time
--     为科学计数法(2.02E+13=20200000000000)，仅精确到年份2020，月/日/时为00已丢失。
--     故仅取 year=2020，其余日期置 NULL，绝不据此过滤整行；时间维度用 order.startTime。
--   ③ charging_fees=0 是数据集常态(3016/3395)，不是脏数据，DWD 一律保留。
--   ④ 真正剔除的脏数据：kwhTotal<=0、chargeTimeHrs<=0 等物理上不可能的记录。
-- 执行：spark-sql --conf spark.sql.shuffle.partitions=20 -f 01_dwd_charge_detail.sql
--       或  sh 01_etl_dwd.sh
-- =====================================================================
SET spark.sql.shuffle.partitions = 20;
SET spark.sql.parquet.compression.codec = snappy;

CREATE DATABASE IF NOT EXISTS ncs_dwd;

DROP TABLE IF EXISTS ncs_dwd.dwd_charge_detail;
CREATE EXTERNAL TABLE ncs_dwd.dwd_charge_detail (
  session_id      STRING  COMMENT '充电会话ID(订单主键)',
  user_id         STRING  COMMENT '用户ID',
  station_id      STRING  COMMENT '充电站ID',
  location_id     STRING  COMMENT '区域ID',
  station_name    STRING  COMMENT '充电站名称',
  address         STRING  COMMENT '充电站地址',
  facility_type   STRING  COMMENT '设施类型编码(1交流/2直流/3交直流一体/4其他)',
  station_type    STRING  COMMENT '设施类型中文名',
  device_count    INT     COMMENT '站点充电桩数量',
  platform        STRING  COMMENT '下单平台(ios/android/web)',
  manager_vehicle INT     COMMENT '是否管理车辆(1是0否)',
  kwh             DOUBLE  COMMENT '充电电量(度)',
  total_fee       DOUBLE  COMMENT '充电费用(元)',
  duration_hrs    DOUBLE  COMMENT '充电时长(小时)',
  start_hour      INT     COMMENT '充电开始小时(0-23)',
  end_hour        INT     COMMENT '充电结束小时(0-23)',
  weekday         STRING  COMMENT '星期几(Mon..Sun)',
  is_weekend      INT     COMMENT '是否周末(1/0)',
  soc             DOUBLE  COMMENT 'BMS 剩余电量%(无明细为NULL)',
  pack_voltage    DOUBLE  COMMENT 'BMS 电池组电压(V)',
  charge_current  DOUBLE  COMMENT 'BMS 充电电流(A)',
  max_temp        DOUBLE  COMMENT 'BMS 最高温度(℃)',
  min_temp        DOUBLE  COMMENT 'BMS 最低温度(℃)',
  start_time      STRING  COMMENT '充电开始时间(record_time仅精确到年,置NULL)',
  charge_date     STRING  COMMENT '充电日期(record_time精度不足,置NULL)',
  year            INT     COMMENT '数据年份(2020,来自record_time前4位)',
  month           INT     COMMENT '月(源数据精度丢失,恒NULL)',
  day             INT     COMMENT '日(源数据精度丢失,恒NULL)'
)
COMMENT 'DWD 充电明细事实表（清洗 + 维度退化 + 时间扩展，一次充电一行）'
STORED AS orc
LOCATION '/user/hive/warehouse/ncs_dwd.db/dwd_charge_detail';

INSERT OVERWRITE TABLE ncs_dwd.dwd_charge_detail
SELECT
    o.sessionId                                                    AS session_id,
    o.userId                                                       AS user_id,
    o.stationId                                                    AS station_id,
    o.locationId                                                   AS location_id,
    m.station_name                                                 AS station_name,
    m.address                                                      AS address,
    o.facilityType                                                 AS facility_type,
    CASE o.facilityType WHEN '1' THEN '交流桩'
                        WHEN '2' THEN '直流桩'
                        WHEN '3' THEN '交直流一体桩'
                        ELSE '其他类型' END                         AS station_type,
    CAST(COALESCE(NULLIF(m.device_count,''), '0') AS INT)          AS device_count,
    lower(o.platform)                                              AS platform,
    CAST(COALESCE(NULLIF(o.managerVehicle,''), '0') AS INT)        AS manager_vehicle,
    CAST(o.kwhTotal AS DOUBLE)                                     AS kwh,
    CAST(o.charging_fees AS DOUBLE)                                AS total_fee,
    CAST(o.chargeTimeHrs AS DOUBLE)                                AS duration_hrs,
    CAST(o.startTime AS INT)                                       AS start_hour,
    CAST(o.endTime AS INT)                                         AS end_hour,
    o.weekday                                                      AS weekday,
    CASE WHEN o.weekday IN ('Sat','Sun') THEN 1 ELSE 0 END         AS is_weekend,
    CAST(p.soc AS DOUBLE)                                          AS soc,
    CAST(p.pack_voltage AS DOUBLE)                                 AS pack_voltage,
    CAST(p.charge_current AS DOUBLE)                               AS charge_current,
    CAST(p.max_temperature AS DOUBLE)                              AS max_temp,
    CAST(p.min_temperature AS DOUBLE)                              AS min_temp,
    -- start_time / charge_date 本应由 record_time 解码，但源字段仅精确到年份，
    -- 2020 年以外的月日时全部为 00（非法），故诚实置 NULL，不臆造时间。
    CAST(NULL AS STRING)                                           AS start_time,
    CAST(NULL AS STRING)                                           AS charge_date,
    -- record_time 全为 2.02E+13=20200000000000，科学计数法仅精确到年份(2020)，
    -- 月/日/时已丢失(均为00)。故 year 可靠=2020，其余置 NULL，不臆造时间。
    -- 小时维度分析统一使用订单自带的 startTime(0-23)，与本字段无关。
    CAST(substr(CAST(CAST(p.record_time AS DOUBLE) AS BIGINT),1,4) AS INT) AS year,
    CAST(NULL AS INT)                                              AS month,
    CAST(NULL AS INT)                                              AS day
FROM ncs_ods.ods_charging_order o
LEFT JOIN ncs_ods.ods_charging_process p
       ON o.sessionId = p.esd
LEFT JOIN ncs_ods.ods_charging_station_meta m
       ON o.stationId = m.stationId
WHERE CAST(o.kwhTotal AS DOUBLE) > 0
  AND CAST(o.chargeTimeHrs AS DOUBLE) > 0;

-- ------------------------- 数据验证（务必确认行数非 0） -------------------------
SELECT 'dwd_charge_detail 总行数'  AS metric, COUNT(*)                AS value FROM ncs_dwd.dwd_charge_detail
UNION ALL SELECT '有BMS明细行数',     COUNT(soc)                        FROM ncs_dwd.dwd_charge_detail
UNION ALL SELECT '用户数',            COUNT(DISTINCT user_id)           FROM ncs_dwd.dwd_charge_detail
UNION ALL SELECT '站点数',            COUNT(DISTINCT station_id)        FROM ncs_dwd.dwd_charge_detail
UNION ALL SELECT '总电量(度)',        ROUND(SUM(kwh),2)                 FROM ncs_dwd.dwd_charge_detail
UNION ALL SELECT '总费用(元)',        ROUND(SUM(total_fee),2)           FROM ncs_dwd.dwd_charge_detail;
