/* ============================================================
   Đếm unique wireless client trong 7 NGÀY FULL gần nhất
   - Mỗi MAC chỉ được tính 1 lần
   - Mỗi MAC được gán vào cặp (model, wifi_standard)
     xuất hiện nhiều log nhất trong 7 ngày
   ============================================================ */

WITH client_model_standard_count AS
(
    SELECT
        mac_client,

        /* Gộp 2 model thành 1 nhóm */
        multiIf(
            model IN ('AP-AX3000C', 'AP-AX3000CV2'),
                'AP-AX3000C/CV2',
            model
        ) AS model_group,

        /* Map MCS standard -> Wi-Fi generation */
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
        ) AS wifi_standard,

        count() AS log_count

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

        /* 7 ngày FULL gần nhất theo Asia/Ho_Chi_Minh
           Ví dụ hôm nay 28 => lấy ngày 21 -> 27
        */
        AND created_at >=
            toTimeZone(
                toStartOfDay(
                    toTimeZone(now(), 'Asia/Ho_Chi_Minh')
                ) - INTERVAL 1 DAY,
                'UTC'
            )

        AND created_at <
            toTimeZone(
                toStartOfDay(
                    toTimeZone(now(), 'Asia/Ho_Chi_Minh')
                ),
                'UTC'
            )

        /* Loại timestamp lỗi */
        AND toYear(created_at) <> 2030

        /* Loại MAC rỗng */
        AND mac_client != ''

    GROUP BY
        mac_client,
        model_group,
        wifi_standard
),

dominant_pair AS
(
    SELECT
        mac_client,

        /* Chọn cặp model + Wi-Fi standard
           có nhiều log nhất của MAC trong 7 ngày */
        argMax(
            tuple(model_group, wifi_standard),
            log_count
        ) AS dominant

    FROM client_model_standard_count

    GROUP BY mac_client
)

SELECT
    dominant.1 AS model,
    dominant.2 AS wifi_standard,
    count() AS unique_clients

FROM dominant_pair

GROUP BY
    model,
    wifi_standard

ORDER BY
    model,
    unique_clients DESC;