WITH
    toDate('2026-09-17') AS start_date,
    toDate('2026-09-24') AS end_date,

/* ============================================================
   1. Base logs
   - AX3000HV2 only
   - 19:00 - 21:00 Asia/Ho_Chi_Minh
   - Split 2.4GHz / 5GHz
   ============================================================ */
base_logs AS
(
    SELECT
        toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) AS local_date,

        mac_address,
        mac_client,

        CASE
            WHEN interface IN (
                '2.4GHz',
                'ath0',
                'ath01',
                'ath02',
                'ath03',
                'wlan5'
            )
                THEN '2.4GHz'
            ELSE '5GHz'
        END AS band,

        rssi

    FROM client_logs_distributed

    WHERE
        /* Partition pruning */
        date >= start_date - 1
        AND date <= end_date + 1

        /* Exact VN date */
        AND toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) BETWEEN start_date AND end_date

        /* 19:00 - 21:00 VN */
        AND toHour(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) >= 19

        AND toHour(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) < 21

        AND model = 'AX3000HV2'
        AND interface_type = 'wireless'

        AND mac_client != ''

        /* Valid RSSI */
        AND rssi >= -90
        AND rssi <= -10
),

/* ============================================================
   2. Per client + CPE + band + day
   - Count logs
   - Mean RSSI
   ============================================================ */
client_daily AS
(
    SELECT
        local_date,
        mac_address,
        mac_client,
        band,

        count() AS log_count,
        avg(rssi) AS mean_rssi

    FROM base_logs

    GROUP BY
        local_date,
        mac_address,
        mac_client,
        band
),

/* ============================================================
   3. Attach daily log threshold
   ============================================================ */
client_with_threshold AS
(
    SELECT
        local_date,
        mac_address,
        mac_client,
        band,
        log_count,
        mean_rssi,

        multiIf(
            local_date = toDate('2026-09-17'), 38,
            local_date = toDate('2026-09-18'), 35,
            local_date = toDate('2026-09-19'), 35,
            local_date = toDate('2026-09-20'), 36,
            local_date = toDate('2026-09-21'), 37,
            local_date = toDate('2026-09-22'), 37,
            local_date = toDate('2026-09-23'), 36,
            local_date = toDate('2026-09-24'), 33,
            999999
        ) AS log_threshold

    FROM client_daily
),

/* ============================================================
   4. Keep only clients reaching daily log threshold
   ============================================================ */
eligible_clients AS
(
    SELECT
        local_date,
        mac_address,
        mac_client,
        band,
        log_threshold,
        mean_rssi

    FROM client_with_threshold

    WHERE log_count < log_threshold
),

/* ============================================================
   5. Calculate coverage per CPE + day + band

   2.4GHz good: mean RSSI >= -74
   5GHz   good: mean RSSI >= -77

   Coverage =
       good eligible clients
       ---------------------
       all eligible clients
   ============================================================ */
cpe_daily_coverage AS
(
    SELECT
        local_date,
        mac_address,
        band,

        any(log_threshold) AS log_threshold,

        count() AS eligible_clients,

        countIf(
            if(
                band = '2.4GHz',
                mean_rssi >= -74,
                mean_rssi >= -77
            )
        ) AS good_clients,

        countIf(
            if(
                band = '2.4GHz',
                mean_rssi >= -74,
                mean_rssi >= -77
            )
        )
        / count()
        * 100.0 AS coverage

    FROM eligible_clients

    GROUP BY
        local_date,
        mac_address,
        band
)

/* ============================================================
   6. Coverage percentile across CPEs
   ============================================================ */
SELECT
    local_date AS date,
    band,
    any(log_threshold) AS threshold,

    round(
        quantileExact(0.10)(coverage),
        2
    ) AS p10,

    round(
        quantileExact(0.20)(coverage),
        2
    ) AS p20,

    round(
        quantileExact(0.30)(coverage),
        2
    ) AS p30,

    round(
        quantileExact(0.40)(coverage),
        2
    ) AS p40,

    round(
        quantileExact(0.50)(coverage),
        2
    ) AS p50,

    round(
        quantileExact(0.55)(coverage),
        2
    ) AS p55,

    round(
        quantileExact(0.60)(coverage),
        2
    ) AS p60,

    round(
        quantileExact(0.65)(coverage),
        2
    ) AS p65,

    round(
        quantileExact(0.70)(coverage),
        2
    ) AS p70,


    round(
        quantileExact(0.99)(coverage),
        2
    ) AS p99

FROM cpe_daily_coverage

GROUP BY
    local_date,
    band

ORDER BY
    local_date,
    CASE band
        WHEN '2.4GHz' THEN 1
        WHEN '5GHz'   THEN 2
        ELSE 99
    END;