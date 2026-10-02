WITH
    toDate('2026-09-27') AS start_date, -- CN
    toDate('2026-09-28') AS end_date,   -- T2

client_daily AS
(
    SELECT
        toDate(
            toTimeZone(created_at, 'Asia/Ho_Chi_Minh')
        ) AS local_date,

        mac_client,

        multiIf(
            interface IN ('2.4GHz', 'ath0', 'ath01', 'ath02', 'ath03', 'wlan5'),
            '2.4GHz',
            '5GHz'
        ) AS band,

        count() AS log_count,

        -- tinh trung binh rssi cua moi unique client
        avg(rssi) AS avg_rssi, 

        -- tinh trung binh PHYRATE (tx_rate) cua moi unique client
        avgIf(tx_rate, tx_rate > 0) AS avg_tx_rate

    FROM client_logs_distributed

    PREWHERE
        date >= start_date - 1
        AND date <= end_date + 1

    WHERE
        toDate(
            toTimeZone(created_at, 'Asia/Ho_Chi_Minh')
        ) BETWEEN start_date AND end_date

        AND toHour(
            toTimeZone(created_at, 'Asia/Ho_Chi_Minh')
        ) >= 19

        AND toHour(
            toTimeZone(created_at, 'Asia/Ho_Chi_Minh')
        ) < 21

        AND model = 'AX3000HV2'
        AND interface_type = 'wireless'
        AND mac_client != ''

    GROUP BY
        local_date,
        mac_client,
        band
),

with_threshold AS
(
    SELECT
        *,
        -- Dat threshold theo p30 log ngay 27, 28 va band 2g, 5g
        multiIf(
            local_date = toDate('2026-09-27') AND band = '2.4GHz', 25,
            local_date = toDate('2026-09-27') AND band = '5GHz',   19,

            local_date = toDate('2026-09-28') AND band = '2.4GHz', 24,
            local_date = toDate('2026-09-28') AND band = '5GHz',   19,

            999999
        ) AS p30_threshold

    FROM client_daily
),

-- chia data theo threshold
classified AS 
(
    SELECT
        *,

        if(
            log_count >= p30_threshold,
            '>= P30',
            '< P30'
        ) AS section

    FROM with_threshold
),

-- bucket cac client theo tung moc rssi
bucketed AS
(
    SELECT
        local_date,
        band,
        section,
        mac_client,
        avg_tx_rate,

        multiIf(
            avg_rssi <= -80, '<= -80',
            avg_rssi <= -70, '-80 to -70',
            avg_rssi <= -60, '-70 to -60',
            avg_rssi <= -50, '-60 to -50',
            avg_rssi <= -40, '-50 to -40',
            avg_rssi <= -30, '-40 to -30',
            '> -30'
        ) AS rssi_bucket,

        multiIf(
            avg_rssi <= -80, 1,
            avg_rssi <= -70, 2,
            avg_rssi <= -60, 3,
            avg_rssi <= -50, 4,
            avg_rssi <= -40, 5,
            avg_rssi <= -30, 6,
            7
        ) AS bucket_order

    FROM classified

    WHERE avg_tx_rate > 0
)

SELECT
    section,

    local_date AS date,

    band,

    rssi_bucket,

    uniqExact(mac_client) AS unique_client_count,

    round(avg(avg_tx_rate), 2) AS mean_tx_rate,

    round(quantileExact(0.10)(avg_tx_rate), 2) AS p10_tx_rate,
    round(quantileExact(0.20)(avg_tx_rate), 2) AS p20_tx_rate,
    round(quantileExact(0.30)(avg_tx_rate), 2) AS p30_tx_rate,
    round(quantileExact(0.40)(avg_tx_rate), 2) AS p40_tx_rate,
    round(quantileExact(0.50)(avg_tx_rate), 2) AS p50_tx_rate,
    round(quantileExact(0.60)(avg_tx_rate), 2) AS p60_tx_rate,
    round(quantileExact(0.70)(avg_tx_rate), 2) AS p70_tx_rate,
    round(quantileExact(0.80)(avg_tx_rate), 2) AS p80_tx_rate,
    round(quantileExact(0.90)(avg_tx_rate), 2) AS p90_tx_rate,
    round(quantileExact(0.95)(avg_tx_rate), 2) AS p95_tx_rate,
    round(quantileExact(0.99)(avg_tx_rate), 2) AS p99_tx_rate

FROM bucketed

GROUP BY
    section,
    local_date,
    band,        -- chia band 2g, 5g
    rssi_bucket, -- tinh phyrate theo rssi bucket
    bucket_order

ORDER BY
    if(section = '>= P30', 1, 2),
    band,
    local_date,
    bucket_order;