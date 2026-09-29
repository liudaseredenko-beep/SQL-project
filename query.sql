WITH account_metrics AS (
    -- 1. Метрики по акаунтах (date = дата створення акаунта)
    SELECT
        s.date AS date,
        sp.country AS country,
        a.send_interval AS send_interval,
        a.is_verified AS is_verified,
        a.is_unsubscribed AS is_unsubscribed,
        COUNT(DISTINCT a.id) AS account_cnt,
        0 AS sent_msg,
        0 AS open_msg,
        0 AS visit_msg
    FROM `data-analytics-mate.DA.account` a
    JOIN `data-analytics-mate.DA.account_session` acs ON a.id = acs.account_id
    JOIN `data-analytics-mate.DA.session` s ON acs.ga_session_id = s.ga_session_id
    JOIN `data-analytics-mate.DA.session_params` sp ON s.ga_session_id = sp.ga_session_id
    GROUP BY
        s.date,
        sp.country,
        a.send_interval,
        a.is_verified,
        a.is_unsubscribed
),




email_metrics AS (
    -- 2. Метрики по емейлах (date = дата відправки листа)
    SELECT
        DATE_ADD(s.date, INTERVAL es.sent_date DAY) AS date,
        sp.country AS country,
        a.send_interval AS send_interval,
        a.is_verified AS is_verified,
        a.is_unsubscribed AS is_unsubscribed,
        0 AS account_cnt,
        COUNT(DISTINCT es.id_message) AS sent_msg,
        COUNT(DISTINCT eo.id_message) AS open_msg,
        COUNT(DISTINCT ev.id_message) AS visit_msg
    FROM `data-analytics-mate.DA.email_sent` es
    JOIN `data-analytics-mate.DA.account` a ON es.id_account = a.id
    JOIN `data-analytics-mate.DA.account_session` acs ON a.id = acs.account_id
    JOIN `data-analytics-mate.DA.session` s ON acs.ga_session_id = s.ga_session_id
    JOIN `data-analytics-mate.DA.session_params` sp ON s.ga_session_id = sp.ga_session_id
    LEFT JOIN `data-analytics-mate.DA.email_open` eo
        ON es.id_account = eo.id_account
       AND es.id_message = eo.id_message
    LEFT JOIN `data-analytics-mate.DA.email_visit` ev
        ON es.id_account = ev.id_account
       AND es.id_message = ev.id_message
    GROUP BY
        DATE_ADD(s.date, INTERVAL es.sent_date DAY),
        sp.country,
        a.send_interval,
        a.is_verified,
        a.is_unsubscribed
),




combined_data AS (
    -- 3. Об'єднання метрик та агрегація однакових груп
    SELECT
        date,
        country,
        send_interval,
        is_verified,
        is_unsubscribed,
        SUM(account_cnt) AS account_cnt,
        SUM(sent_msg) AS sent_msg,
        SUM(open_msg) AS open_msg,
        SUM(visit_msg) AS visit_msg
    FROM (
        SELECT * FROM account_metrics
        UNION ALL
        SELECT * FROM email_metrics
    ) raw_metrics
    GROUP BY
        date,
        country,
        send_interval,
        is_verified,
        is_unsubscribed
),




country_totals AS (
    -- 4. Розрахунок загальних сум по країнах
    SELECT
        date,
        country,
        send_interval,
        is_verified,
        is_unsubscribed,
        account_cnt,
        sent_msg,
        open_msg,
        visit_msg,
        SUM(account_cnt) OVER (PARTITION BY country) AS total_country_account_cnt,
        SUM(sent_msg) OVER (PARTITION BY country) AS total_country_sent_cnt
    FROM combined_data
),




ranked_data AS (
    -- 5. Розрахунок рангів на основі вже обчислених сум по країнах
    SELECT
        *,
        DENSE_RANK() OVER (ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt,
        DENSE_RANK() OVER (ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt
    FROM country_totals
)




-- 6. Фінальний вибір із фільтрацією за ТОП-10 країнами
SELECT
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    account_cnt,
    sent_msg,
    open_msg,
    visit_msg,
    total_country_account_cnt,
    total_country_sent_cnt,
    rank_total_country_account_cnt,
    rank_total_country_sent_cnt
FROM ranked_data
WHERE rank_total_country_account_cnt <= 10
   OR rank_total_country_sent_cnt <= 10
ORDER BY date DESC, country;
