/* ============================================================
   Thống kê theo MODEL trong N ngày FULL gần nhất

   Total device = unique mac_address (CPE/AP)
   WiFi 4-7     = unique mac_client theo dominant standard
   Total        = tổng unique client WiFi 4-7

   NOTE: QUERY TỐN ~ 50P ĐỂ CHẠY, CÂN NHẮC TRƯỚC KHI RUN
   ============================================================ */

WITH

/* ============================================================
   1. Raw data trong khoảng thời gian cần phân tích
   ============================================================ */
base_data AS
(
    SELECT
        mac_address,
        mac_client,

        /* Gộp model */
        multiIf(
            model IN ('AP-AX3000C', 'AP-AX3000CV2'),
            'AP-AX3000C/CV2',
            model
        ) AS model_group,

        /* Map MCS -> Wi-Fi generation */
        multiIf(
            tx_mcs_standard IN ('-', ''),
                'NULL_STANDARD',

            tx_mcs_standard IN ('EHT', 'EHT_map'),
                'WiFi 7',

            tx_mcs_standard IN ('HE', 'HE_SU'),
                'WiFi 6',

            tx_mcs_standard = 'VHT',
                'WiFi 5',

            tx_mcs_standard IN ('HT', 'HT_MM', 'OFDM', 'CCK'),
                'WiFi 4',

            'Unknown'
        ) AS wifi_standard

    FROM cpe_log.client_logs_distributed

    WHERE
        interface_type = 'wireless'

        AND model IN (
            'AP-AX3000C',
            'AP-AX3000CV2',
            'AX3000HV2',
            'AX3000S',
            'ONT-BE6500C',
            'AX3000GZV3'
        )

        /* N ngày FULL gần nhất.
        */
        AND created_at >=
            toTimeZone(
                toStartOfDay(
                    toTimeZone(now(), 'Asia/Ho_Chi_Minh')
                ) - INTERVAL 6 DAY,
                'UTC'
            )

        AND created_at <
            toTimeZone(
                toStartOfDay(
                    toTimeZone(now(), 'Asia/Ho_Chi_Minh')
                ),
                'UTC'
            )

        AND toYear(created_at) <> 2030
),

/* ============================================================
   2. Đếm TOTAL DEVICE theo model
      1 device = 1 unique mac_address
   ============================================================ */
device_count AS
(
    SELECT
        model_group,
        uniqExact(mac_address) AS total_device
    FROM base_data

    WHERE mac_address != ''

    GROUP BY model_group
),

/* ============================================================
   3. Đếm số log của từng:
      mac_client + model + wifi_standard
   ============================================================ */
client_standard_count AS
(
    SELECT
        mac_client,
        model_group,
        wifi_standard,
        count() AS log_count

    FROM base_data

    WHERE mac_client != ''

    GROUP BY
        mac_client,
        model_group,
        wifi_standard
),

/* ============================================================
   4. Mỗi mac_client chỉ giữ đúng 1 cặp
      (model, wifi_standard) có nhiều log nhất

      => tránh overlap:
         một client không bị count cả WiFi 5 và WiFi 6
   ============================================================ */
dominant_client AS
(
    SELECT
        mac_client,

        argMax(
            tuple(model_group, wifi_standard),
            log_count
        ) AS dominant

    FROM client_standard_count

    GROUP BY mac_client
),

/* ============================================================
   5. Pivot WiFi 4 / 5 / 6 / 7 theo model
   ============================================================ */
client_count AS
(
    SELECT
        dominant.1 AS model_group,

        countIf(dominant.2 = 'WiFi 4') AS wifi_4,
        countIf(dominant.2 = 'WiFi 5') AS wifi_5,
        countIf(dominant.2 = 'WiFi 6') AS wifi_6,
        countIf(dominant.2 = 'WiFi 7') AS wifi_7,

        /* Total chỉ tính client thuộc WiFi 4 -> 7 */
        countIf(
            dominant.2 IN (
                'WiFi 4',
                'WiFi 5',
                'WiFi 6',
                'WiFi 7'
            )
        ) AS total_clients

    FROM dominant_client

    GROUP BY model_group
)

/* ============================================================
   6. Output cuối
   ============================================================ */
SELECT
    d.model_group AS model,
    d.total_device AS total_device,

    ifNull(c.wifi_4, 0) AS wifi_4,
    ifNull(c.wifi_5, 0) AS wifi_5,
    ifNull(c.wifi_6, 0) AS wifi_6,
    ifNull(c.wifi_7, 0) AS wifi_7,

    ifNull(c.total_clients, 0) AS total

FROM device_count d

LEFT JOIN client_count c
    ON d.model_group = c.model_group

ORDER BY d.total_device DESC;