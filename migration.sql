-- shipping_country_rates

CREATE TABLE public.shipping_country_rates (
    id SERIAL PRIMARY KEY,
    shipping_country TEXT,
    shipping_country_base_rate DECIMAL(14,3)
);

INSERT INTO public.shipping_country_rates
(shipping_country, shipping_country_base_rate)
SELECT DISTINCT shipping_country, shipping_country_base_rate
FROM public.shipping;

-- shipping_agreement

CREATE TABLE public.shipping_agreement (
    agreementid BIGINT PRIMARY KEY,
    agreement_number TEXT,
    agreement_rate DECIMAL(14,3),
    agreement_commission DECIMAL(14,3)
);

INSERT INTO public.shipping_agreement
(agreementid, agreement_number, agreement_rate, agreement_commission)
WITH
cte_vad AS (
    SELECT string_to_array(vendor_agreement_description, ':') vad
    FROM public.shipping
)
SELECT DISTINCT
    vad[1]::BIGINT agreementid,
    vad[2] agreement_number,
    vad[3]::DECIMAL(14,3) agreement_rate,
    vad[4]::DECIMAL(14,3) agreement_commission
FROM cte_vad
;

-- shipping_transfer

CREATE TABLE public.shipping_transfer (
    id SERIAL PRIMARY KEY,
    transfer_type TEXT,
    transfer_model TEXT,
    shipping_transfer_rate DECIMAL(14,3)
);

INSERT INTO public.shipping_transfer
(transfer_type, transfer_model, shipping_transfer_rate)
WITH cte_shipping_transfer AS (
    SELECT
        string_to_array(shipping_transfer_description, ':') descr,
        shipping_transfer_rate
    FROM public.shipping
)
SELECT DISTINCT descr[1], descr[2], shipping_transfer_rate
FROM cte_shipping_transfer;

-- shipping_info

CREATE TABLE public.shipping_info (
    shippingid                BIGINT PRIMARY KEY,
    shipping_transfer_id      BIGINT NOT NULL,
    agreementid               BIGINT NOT NULL,
    shipping_country_rates_id BIGINT NOT NULL,
    shipping_plan_datetime    TIMESTAMP NOT NULL,
    payment_amount            DECIMAL(14,2) NOT NULL,
    vendorid                  BIGINT NOT NULL,
    FOREIGN KEY (shipping_transfer_id)
        REFERENCES public.shipping_transfer(id), -- NO ACTION
    FOREIGN KEY (agreementid)
        REFERENCES public.shipping_agreement(agreementid), -- NO ACTION
    FOREIGN KEY (shipping_country_rates_id)
        REFERENCES public.shipping_country_rates(id) -- NO ACTION
);

INSERT INTO public.shipping_info
(
    shippingid,
    shipping_transfer_id,
    agreementid,
    shipping_country_rates_id,
    shipping_plan_datetime,
    payment_amount,
    vendorid
)
WITH cte_arrays AS (
    SELECT
        shippingid,
        shipping_plan_datetime,
        payment_amount,
        vendorid,
        string_to_array(shipping_transfer_description, ':') t_descr,
        shipping_transfer_rate,
        string_to_array(vendor_agreement_description, ':') as "vad",
        shipping_country,
        shipping_country_base_rate
    FROM
        public.shipping
) SELECT DISTINCT
    shippingid,
    t.id,
    a.agreementid,
    r.id,
    shipping_plan_datetime,
    payment_amount,
    vendorid
FROM
    cte_arrays "arr"
    INNER JOIN public.shipping_transfer "t" ON (
        t.transfer_type = arr.t_descr[1]
        AND t.transfer_model = arr.t_descr[2]
        AND t.shipping_transfer_rate = arr.shipping_transfer_rate
    )
    INNER JOIN public.shipping_agreement "a" ON a.agreementid = arr.vad[1]::BIGINT
    INNER JOIN public.shipping_country_rates "r" ON (
        r.shipping_country = arr.shipping_country
        AND r.shipping_country_base_rate = arr.shipping_country_base_rate
    )
;

-- shipping_status

CREATE TABLE public.shipping_status (
    shippingid BIGINT PRIMARY KEY,
    status TEXT,
    state TEXT,
    shipping_start_fact_datetime TIMESTAMP DEFAULT NULL,
    shipping_end_fact_datetime TIMESTAMP DEFAULT NULL
);

INSERT INTO public.shipping_status
(shippingid, status, state, shipping_start_fact_datetime, shipping_end_fact_datetime)
WITH
cte_max_state_datetime AS (
    SELECT shippingid, MAX(state_datetime) AS dt
    FROM public.shipping
    GROUP BY shippingid
)
SELECT
    s.shippingid,
    s.status,
    s.state,
    b.state_datetime,
    r.state_datetime
FROM
    cte_max_state_datetime m
    INNER JOIN public.shipping s ON (
        s.shippingid = m.shippingid
        AND s.state_datetime = m.dt
    )
    LEFT JOIN public.shipping b ON (
        b.shippingid = m.shippingid
        AND b.state = 'booked'
    )
    LEFT JOIN public.shipping r ON (
        r.shippingid = m.shippingid
        AND r.state = 'recieved'
    )
;


-- два апдейта ниже нужны были бы, если бы на каждый shippingid
-- бфло несколько записей со state-ом 'booked' или 'recieved',
-- но это не так (см. проверки в readme.md);
-- пускай будут закомментированными, на память, что можно делать проверки
-- и упрощать сиквел для миграции.

-- UPDATE public.shipping_status s
-- SET (shipping_start_fact_datetime) =
-- (
--     WITH
--     cte_min_booked AS (
--         SELECT shippingid, MIN(state_datetime) AS dt
--         FROM public.shipping
--         WHERE state = 'booked'
--         GROUP BY shippingid
--     )
--     SELECT dt
--     FROM cte_min_booked b
--     WHERE b.shippingid = s.shippingid
-- );
-- 
-- UPDATE public.shipping_status s
-- SET (shipping_end_fact_datetime) =
-- (
--     WITH
--     cte_min_recieved AS (
--         SELECT shippingid, MIN(state_datetime) AS dt
--         FROM public.shipping
--         WHERE state = 'recieved'
--         GROUP BY shippingid
--     )
--     SELECT dt
--     FROM cte_min_recieved r
--     WHERE r.shippingid = s.shippingid
-- );

-- view shipping_datamart

CREATE OR REPLACE VIEW public.shipping_datamart AS
SELECT
      i."shippingid"
    , i."vendorid"
    , t."transfer_type"
    , EXTRACT(
        DAY FROM age(s.shipping_end_fact_datetime, s.shipping_start_fact_datetime)
      ) as "full_day_at_shipping"
    , (CASE
        WHEN s.shipping_end_fact_datetime > i.shipping_plan_datetime THEN 1
        ELSE 0
      END) as "is_delay"
    , (CASE
        WHEN s.status = 'finished' THEN 1
        ELSE 0
      END) as "is_shipping_finish"
    , (CASE
        WHEN s.shipping_end_fact_datetime > i.shipping_plan_datetime
          THEN EXTRACT (DAY FROM age(s.shipping_end_fact_datetime, i.shipping_plan_datetime))
        ELSE 0
      END) as "delay_day_at_shipping"
    , i."payment_amount"
    , i.payment_amount * (
        r.shipping_country_base_rate + a.agreement_rate + t.shipping_transfer_rate
      ) as "vat"
    , (i.payment_amount * a.agreement_commission) as "profit"
FROM
    public.shipping_info i
    INNER JOIN public.shipping_status s ON s.shippingid = i.shippingid
    INNER JOIN public.shipping_transfer t ON t.id = i.shipping_transfer_id
    INNER JOIN public.shipping_agreement a ON a.agreementid = i.agreementid
    INNER JOIN public.shipping_country_rates r ON r.id = i.shipping_country_rates_id
;