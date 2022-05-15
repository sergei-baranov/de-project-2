# Проект 2
Опишите здесь поэтапно ход решения задачи. Вы можете ориентироваться на тот план выполнения проекта, который мы предлагаем в инструкции на платформе.

## 1. Создаём источник (dump.sql)

### 1.1. Окружение

БД будет в докере, например в том, который шёл под модуль, по которому этот проект.

В подключаемый volume, который изнутри виден как /lessons, копируем файлы:
- shipping.csv,
- dump.sql,
- migration.sql,
- rollback.sql.

Запускаем контейнер

```
$ sudo docker run -d --rm -p 3000:3000 -p 15432:5432 -v /home/s_baranov/YA_DE/sprint3_lessons:/lessons --name=de-sprint-2-server-local sindb/sprint-2:latest
```

Проверяем контейнер

```
$ sudo docker ps -a
CONTAINER ID   IMAGE ...
2db1e9e5dea3   sindb/sprint-2:latest ...
```

Заходим в контейнер, он у нас получил ид 2db1e9e5dea3

```
$ sudo docker exec -it 2db1e9e5dea3 bash
root@2db1e9e5dea3:/agent#
```

---

### 1.2. Исполняем dump.sql

В dump.sql создаётся таблица public.shipping, и в неё вызывается COPY из csv-файла

В контейнере отправляем на исполнение psql-ом /lessons/dump.sql:

```
root@2db1e9e5dea3:/agent# psql postgresql://jovyan:jovyan@localhost:5432/de < /lessons/dump.sql
NOTICE:  table "shipping" does not exist, skipping
DROP TABLE
CREATE TABLE
CREATE INDEX
COMMENT
COPY 324770
root@2db1e9e5dea3:/agent#
```

Инструкции исполнены, данные загружены.

Проверяем структуру и данные:

```
de=# \d public.shipping

 Table "public.shipping"
            Column             |            Type    | Nullable | Default                
-------------------------------+--------------------+----------+-------------
 id                            | integer            | not null | nextval(...)
 shippingid                    | bigint             |          | 
 saleid                        | bigint             |          | 
 orderid                       | bigint             |          | 
 clientid                      | bigint             |          | 
 payment_amount                | numeric(14,2)      |          | 
 state_datetime                | timestamp          |          |
                               | without time zone  |          | 
 productid                     | bigint             |          | 
 description                   | text               |          | 
 vendorid                      | bigint             |          | 
 namecategory                  | text               |          | 
 base_country                  | text               |          | 
 status                        | text               |          | 
 state                         | text               |          | 
 shipping_plan_datetime        | timestamp          |          |
                               | without time zone  |          | 
 hours_to_plan_shipping        | numeric(14,2)      |          | 
 shipping_transfer_description | text               |          | 
 shipping_transfer_rate        | numeric(14,3)      |          | 
 shipping_country              | text               |          | 
 shipping_country_base_rate    | numeric(14,3)      |          | 
 vendor_agreement_description  | text               |          | 
Indexes:
    "shipping_pkey" PRIMARY KEY, btree (id)
    "shippingid" btree (shippingid)
```

```
de=# SELECT COUNT(*) FROM public.shipping;
 count  
--------
 324770
(1 row)
```

```
de=# SELECT COUNT(DISTINCT productid) FROM public.shipping;
 count 
-------
   188
(1 row)
```

Считаем, что всё норм, источник создан.

## 2. Откат (rollback.sql)

Просто DROP-ает все таблицы последовательно согласно FK между ними.

## 3. Миграция (migration.sql)

Набор sql-стейтментов согласно плана в описании проекта:

1. Создайте справочник стоимости доставки в страны, указанные в `shipping_country_rates`, из данных `shipping_country` и `shipping_country_base_rate`, сделайте первичный ключ таблицы — `серийный id`, то есть серийный идентификатор каждой строчки. Важно дать серийному ключу имя `id`.

--- 

В `migration.sql` создаётся и заполняется таблица `shipping_country_rates`.

Код под комментом `'-- shipping_country_rates'`.

---

2. Создайте справочник тарифов доставки вендора по договору `shipping_agreement` из данных строки `vendor_agreement_description` через разделитель `:`.<br/>
Названия полей: `agreementid`, `agreement_number`, `agreement_rate`, `agreement_commission`.

Поле `agreementid` сделайте первичным ключом.

---

В `migration.sql` создаётся и заполняется таблица `shipping_agreement`.

Код под комментом `'-- shipping_agreement'`.

---

3. Создайте справочник о типах доставки `shipping_transfer` из строки `shipping_transfer_description` через разделитель `:`.
Названия полей: `transfer_type`, `transfer_model`.
Тж. необходимо поле `shipping_transfer_rate`.

Сделайте первичный ключ таблицы — `серийный id`. Подсказка: Важно помнить про размерность знаков после запятой при выделении фиксированной длины в типе numeric(). Например, если shipping_transfer_rate равен 2.5%, то при миграции в тип numeric(14,2) у вас отбросится 0,5%.

---

В `migration.sql` создаётся и заполняется таблица `shipping_transfer`.

Код под комментом `'-- shipping_transfer'`.

---

4. Создайте таблицу `shipping_info` с уникальными доставками `shippingid` и свяжите её с созданными справочниками `shipping_country_rates`, `shipping_agreement`, `shipping_transfer` и константной информацией о доставке `shipping_plan_datetime`, `payment_amount`, `vendorid`.

---

- Проверки на NOT NULL:

```
SELECT COUNT(*) FROM public.shipping WHERE shippingid IS NULL;

SELECT COUNT(*) FROM public.shipping WHERE vendorid IS NULL;

SELECT COUNT(*) FROM public.shipping WHERE shipping_country IS NULL;

SELECT COUNT(*) FROM public.shipping WHERE vendor_agreement_description IS NULL;

SELECT COUNT(*) FROM public.shipping WHERE shipping_transfer_description IS NULL;

SELECT COUNT(*) FROM public.shipping WHERE shipping_plan_datetime IS NULL;

SELECT COUNT(*) FROM public.shipping WHERE payment_amount IS NULL;

По всем запросам

 count 
-------
 0
```

Значит все поля делаем NOT NULL.

- Проверки на уникальность shippingid

```
SELECT shippingid, COUNT(DISTINCT vendorid) cnt
FROM public.shipping
GROUP BY shippingid
HAVING COUNT(DISTINCT vendorid) > 1;
-- 0

SELECT
  shippingid,
  COUNT(DISTINCT CONCAT(shipping_country, '/', shipping_country_base_rate)) cnt
FROM public.shipping
GROUP BY shippingid
HAVING COUNT(DISTINCT CONCAT(shipping_country, '/', shipping_country_base_rate)) > 1;
-- 0

SELECT shippingid, COUNT(DISTINCT vendor_agreement_description) cnt
FROM public.shipping
GROUP BY shippingid
HAVING COUNT(DISTINCT vendor_agreement_description) > 1;
-- 0

SELECT
  shippingid,
  COUNT(DISTINCT CONCAT(shipping_transfer_description, '/', shipping_transfer_rate)) cnt
FROM public.shipping
GROUP BY shippingid
HAVING COUNT(DISTINCT CONCAT(shipping_transfer_description, '/', shipping_transfer_rate)) > 1;
-- 0

SELECT shippingid, COUNT(DISTINCT shipping_plan_datetime) cnt
FROM public.shipping
GROUP BY shippingid
HAVING COUNT(DISTINCT shipping_plan_datetime) > 1;
-- 0

SELECT shippingid, COUNT(DISTINCT payment_amount) cnt
FROM public.shipping
GROUP BY shippingid
HAVING COUNT(DISTINCT payment_amount) > 1;
-- 0
```

Значит возможно выполнение условия "с уникальными доставками `shippingid`"
(сделаем допустим `GROUP BY shippingid`).

---

В `migration.sql` создаётся и заполняется таблица `shipping_info`.

Код под комментом `'-- shipping_info'`.

---

5. Создайте таблицу статусов о доставке `shipping_status` и включите туда информацию из лога `shipping` (`status` , `state`). Добавьте туда вычислимую информацию по фактическому времени доставки `shipping_start_fact_datetime`, `shipping_end_fact_datetime` . Отразите для каждого уникального `shippingid` его итоговое состояние доставки.

- Данные в таблице должны отражать максимальный `status` и `state` по максимальному времени лога `state_datetime` в таблице `shipping`.
- `shipping_start_fact_datetime` — это время `state_datetime`, когда `state` заказа перешёл в состояние `booked`.
- `shipping_end_fact_datetime` — это время `state_datetime` , когда state заказа перешёл в состояние `recieved`.

---

В `migration.sql` создаётся и заполняется таблица `shipping_status`.

Код под комментом `'-- shipping_status'`.

Заполняем данными в три прохода (один инсерт и два апдейта), так как один инсерт с джойнами на 4 CTE-шки работает неприлично долго.

---

6. Создайте представление `shipping_datamart` на основании готовых таблиц для аналитики и включите в него:
- `shippingid`
- `vendorid`
- `transfer_type` — тип доставки из таблицы `shipping_transfer`
- `full_day_at_shipping` — количество полных дней, в течение которых длилась доставка. Высчитывается как: `shipping_end_fact_datetime`-`shipping_start_fact_datetime`.
- `is_delay` — статус, показывающий просрочена ли доставка. Высчитывается как: `shipping_end_fact_datetime` > `shipping_plan_datetime` → 1; 0
- `is_shipping_finish` — статус, показывающий, что доставка завершена. Если финальный `status` = `finished` → 1; 0
- `delay_day_at_shipping` — количество дней, на которые была просрочена доставка. Высчитыается как: `shipping_end_fact_datetime` > `shipping_plan_datetime` → `shipping_end_fact_datetime` - `shipping_plan_datetime` ; 0).
- `payment_amount` — сумма платежа пользователя
- `vat` — итоговый налог на доставку. Высчитывается как: `payment_amount` * ( `shipping_country_base_rate` + `agreement_rate` + `shipping_transfer_rate`).
- `profit` — итоговый доход компании с доставки. Высчитывается как: `payment_amount` * `agreement_commission`.

---

В `migration.sql` создаётся и заполняется представление `shipping_datamart`.

Код под комментом `'-- view shipping_datamart'`.

---