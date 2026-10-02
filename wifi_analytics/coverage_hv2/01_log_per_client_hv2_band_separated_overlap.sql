WITH
    toDate('2026-09-21') AS start_date,
    toDate('2026-09-27') AS end_date,

/* ============================================================
   1. Determine bands seen by each client per day
   ============================================================ */
client_band AS
(
    SELECT
        toDate(
            toTimeZone(
                created_at,
                'Asia/Ho_Chi_Minh'
            )
        ) AS local_date,

        mac_client,

        max(
            interface IN (
                '2.4GHz',
                'ath0',
                'ath01',
                'ath02',
                'ath03',
                'wlan5'
            )
        ) AS has_24g,

        max(
            interface NOT IN (
                '2.4GHz',
                'ath0',
                'ath01',
                'ath02',
                'ath03',
                'wlan5'
            )
        ) AS has_5g

    FROM cpe_log.client_logs_distributed

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

        /* 19:00 - 21:00 VN time */
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
        mac_client
)

/* ============================================================
   2. Calculate overlap
   ============================================================ */
SELECT
    local_date AS date,

    count() AS total_unique_client,

    countIf(has_24g = 1) AS client_24g,

    countIf(has_5g = 1) AS client_5g,

    countIf(
        has_24g = 1
        AND has_5g = 1
    ) AS overlap_client,

    round(
        100.0
        * countIf(has_24g = 1 AND has_5g = 1)
        / count(),
        2
    ) AS overlap_pct

FROM client_band

GROUP BY local_date

ORDER BY local_date;