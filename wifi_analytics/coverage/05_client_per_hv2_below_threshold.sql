WITH
    toDate('2026-09-17') AS start_date,
    toDate('2026-09-24') AS end_date,

/* ============================================================
   1. Count logs per client / CPE / day
   ============================================================ */
client_daily AS
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

        count() AS log_count

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

    GROUP BY
        local_date,
        mac_address,
        mac_client
),

/* ============================================================
   2. Keep clients BELOW daily log threshold
   ============================================================ */
low_log_clients AS
(
    SELECT
        local_date,
        mac_address,
        mac_client

    FROM client_daily

    WHERE
        log_count < multiIf(
            local_date = toDate('2026-09-17'), 38,
            local_date = toDate('2026-09-18'), 35,
            local_date = toDate('2026-09-19'), 35,
            local_date = toDate('2026-09-20'), 36,
            local_date = toDate('2026-09-21'), 37,
            local_date = toDate('2026-09-22'), 37,
            local_date = toDate('2026-09-23'), 36,
            local_date = toDate('2026-09-24'), 33,
            999999
        )
),

/* ============================================================
   3. Number of unique low-log clients per CPE
   ============================================================ */
client_count_per_cpe AS
(
    SELECT
        local_date,
        mac_address,

        uniqExact(mac_client) AS client_count

    FROM low_log_clients

    GROUP BY
        local_date,
        mac_address
)

/* ============================================================
   4. Histogram
   X = number of clients per CPE
   Y = number of CPEs
   ============================================================ */
SELECT
    local_date AS date,

    client_count AS client_count_per_cpe,

    count() AS cpe_count

FROM client_count_per_cpe

GROUP BY
    local_date,
    client_count

ORDER BY
    local_date,
    client_count;