CREATE SCHEMA "energy";
drop SCHEMA  "energy" CASCADE;
 
 -- check the columns of the 3 tables
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'energy'
ORDER BY table_name;

-- rename the table to match the assignment
ALTER TABLE energy.consumption RENAME TO energy_consumption;

-- energy_consumption: SQL-friendly column names
ALTER TABLE energy.energy_consumption RENAME COLUMN "Date" TO date;
ALTER TABLE energy.energy_consumption RENAME COLUMN "Building" TO building;
ALTER TABLE energy.energy_consumption RENAME COLUMN "Water Consumption" TO water_consumption;
ALTER TABLE energy.energy_consumption RENAME COLUMN "Electricity Consumption" TO electricity_consumption;
ALTER TABLE energy.energy_consumption RENAME COLUMN "Gas Consumption" TO gas_consumption;

-- buildings: SQL-friendly column names
ALTER TABLE energy.buildings RENAME COLUMN "Building" TO building;
ALTER TABLE energy.buildings RENAME COLUMN "City" TO city;
ALTER TABLE energy.buildings RENAME COLUMN "Country" TO country;

-- rates: SQL-friendly column names
ALTER TABLE energy.rates RENAME COLUMN "Year" TO year;
ALTER TABLE energy.rates RENAME COLUMN "Energy Type" TO energy_type;
ALTER TABLE energy.rates RENAME COLUMN "Price Per Unit" TO price_per_unit;

-- buildings: building code is the primary key
ALTER TABLE energy.buildings
    ALTER COLUMN building TYPE text;
ALTER TABLE energy.buildings
    ADD PRIMARY KEY (building);

-- energy_consumption: date only (no time part), building code as VARCHAR
ALTER TABLE energy.energy_consumption
    ALTER COLUMN date TYPE DATE;
ALTER TABLE energy.energy_consumption
    ALTER COLUMN building type text;

-- one row per building per date
ALTER TABLE energy.energy_consumption
    ADD PRIMARY KEY (date, building);

-- every building in consumption must exist in buildings
ALTER TABLE energy.energy_consumption
    ADD FOREIGN KEY (building) REFERENCES energy.buildings (building);

-- rates: one price per year per energy type
ALTER TABLE energy.rates
    ALTER COLUMN year TYPE INT;
ALTER TABLE energy.rates
    ADD PRIMARY KEY (year, energy_type);

select * from energy.rates;

-- Unpivot the 3 consumption columns into (energy_type, consumption)
-- using one CTE per energy type + UNION ALL.
-- The original table is not modified; the result is saved as a view.
CREATE OR REPLACE VIEW energy.energy_consumption_unpivoted AS
WITH water AS (
    SELECT date, building, 'Water' AS energy_type, water_consumption AS consumption
    FROM energy.energy_consumption
),
electricity AS (
    SELECT date, building, 'Electricity' AS energy_type, electricity_consumption AS consumption
    FROM energy.energy_consumption
),
gas AS (
    SELECT date, building, 'Gas' AS energy_type, gas_consumption AS consumption
    FROM energy.energy_consumption
)
SELECT * FROM water
UNION ALL
SELECT * FROM electricity
UNION ALL
SELECT * FROM gas;

-- Q1: What is the total consumption for each energy type?
SELECT
    energy_type,
    SUM(consumption) AS total_consumption
FROM energy.energy_consumption_unpivoted
GROUP BY energy_type
ORDER BY total_consumption DESC;

-- Q2: Which building consumes the most energy?
SELECT building,sum(consumption) as total_consumption
from energy.energy_consumption_unpivoted
GROUP BY building
ORDER BY total_consumption DESC
LIMIT 1;

-- Q3: Which city consumes the most energy?

SELECT b.city,
        sum(consumption) as total_consumption
from energy.energy_consumption_unpivoted as e
JOIN energy.buildings b on e.building = b.building
GROUP BY b.city
ORDER BY total_consumption DESC 
LIMIT 1;

-- Q4: What is the average consumption per building?
SELECT building, 
        ROUND(AVG(consumption),2) as avg_consumption
from energy.energy_consumption_unpivoted
GROUP BY building
ORDER BY avg_consumption DESC;

-- Q5: What is the total energy cost by energy type?
--  calculates cost per row (consumption * yearly price)
--  sums the cost per energy type
SELECT energy_type, round(sum(Cost)::NUMERIC ,2) as total_cost
        FROM(
            select e.energy_type, consumption * price_per_unit as Cost
        from energy.energy_consumption_unpivoted as e
        JOIN energy.rates as r on r.year = extract (YEAR from e."date") and 
        r.energy_type = e.energy_type)
GROUP BY energy_type
ORDER BY total_cost DESC;

-- Q6: Which building has the highest energy cost?

SELECT building, round(sum(Cost)::NUMERIC ,2) as total_cost
        FROM (SELECT building, round(consumption * price_per_unit::NUMERIC,2) as Cost
            from energy.energy_consumption_unpivoted as e
            JOIN energy.rates as r ON r.year = extract(YEAR FROM e."date") 
            AND r.energy_type = e.energy_type)
GROUP BY building
ORDER BY total_cost DESC
LIMIT 1;

-- Q7: Which city has the highest energy cost?
SELECT city, round(sum(cost::NUMERIC),2) as total_cost
       from(SELECT city, consumption * price_per_unit as COST
        from energy.energy_consumption_unpivoted as e
        JOIN energy.buildings as b on b.building = e.building
        JOIN energy.rates as r on r.year = extract ( YEAR from e."date") AND
        e.energy_type = r.energy_type)
GROUP BY city
ORDER BY total_cost DESC
LIMIT 1;

-- Q8: Which buildings have an energy cost higher than the average?
-- inner subquery: total cost per building
-- scalar subquery in WHERE: the average of those building totals

create or REPLACE VIEW energy.energy_cost AS
SELECT
e."date",
extract (YEAR from e."date") as year,
b.city,
b.country,
b.building,
e.consumption,
e.energy_type,
r.price_per_unit,
consumption * price_per_unit as COST,
EXTRACT(MONTH FROM e.date)::int AS month, 
TO_CHAR(e.date, 'Month') AS month_name  
FROM energy.energy_consumption_unpivoted e
JOIN energy.buildings as b on e.building = b.building
JOIN energy.rates as r on r.year = extract (YEAR from e."date") AND
e.energy_type = r.energy_type

-- Q8: Which buildings have an energy cost higher than the average?

with building_Cost AS(
        SELECT building, Round(sum(cost)::NUMERIC,2) as total_cost
        from energy.energy_cost
        GROUP BY building
)
SELECT 
        building, 
        total_cost
from building_Cost
WHERE total_cost > (SELECT AVG(total_cost)FROM building_Cost)
ORDER BY total_cost DESC;

-- Q9 (CTE): What is the most expensive energy type for each year?
-- CTE 1: total cost per year and energy type
-- CTE 2: rank the energy types inside each year by cost
with year_cost as (
                SELECT energy_type, year, round(sum(COST)::NUMERIC,2) as total_cost
                FROM energy.energy_cost
                GROUP BY year,energy_type),
ranked as (
        SELECT 
            YEAR,energy_type,total_cost,
            rank() OVER(PARTITION BY year ORDER BY total_cost DESC) as rnk
            from year_cost
)
SELECT YEAR,energy_type,total_cost,rnk
 FROM ranked
 --   WHERE rnk=1
ORDER BY rnk ASC;

-- Extra Q1: What is the average energy cost per building in each city?
-- (fair comparison: cities have a different number of buildings)

with building_cost as 
            (select city,building, round(sum(cost)::NUMERIC,2) as total_cost
            from energy.energy_cost
            GROUP BY city,building
            )
SELECT city, 
            COUNT(*) as number_of_buildings,
             round(AVG(total_cost)::NUMERIC,2) as AVG_cost
from building_cost
GROUP BY city
ORDER BY AVG_cost DESC;

-- Extra Q2: How much did the total cost grow each year compared to the previous year?
-- CTE: total cost per year
-- LAG() reads the previous year's cost so we can calculate the growth %

with yearly_cost as (
    SELECT YEAR,round(sum(cost)::NUMERIC,2) as total_cost
    from energy.energy_cost
    GROUP BY YEAR
)  
SELECT
    year,
     total_cost,
    ROUND(((total_cost - LAG(total_cost) OVER (ORDER BY year))
           / LAG(total_cost) OVER (ORDER BY year) * 100)::numeric, 2) AS growth_pct
FROM yearly_cost
ORDER BY year;

-- Extra Q3: Which months have the highest average electricity consumption?
-- (looking for seasonality across all buildings and years)

WITH monthly as(
    SELECT Month_Name ,extract(month FROM "date") as month_number ,
        AVG(consumption) as avg_con
    from energy.energy_cost
    WHERE energy_type = 'Electricity'
    GROUP BY month_name ,"date"
    )
SELECT
    Month_Number,
    TRIM(month_name) AS month_name,
    ROUND(avg_con, 2) AS avg_electricity_consumption
FROM monthly
ORDER BY avg_electricity_consumption DESC;

-- View: monthly_energy_summary
-- Summary of the latest month available in the dataset (dynamic, no hard-coded month).
-- One row per energy type with consumption, cost, and share of the month's total cost.

create or REPLACE VIEW energy.monthly_energy_summary AS
WITH latest_month AS (
    -- the latest month in the data; recalculated every time the view is queried
    SELECT date_trunc ('month' , MAX(date)) AS month_start
    FROM energy.energy_cost
),
current_month_data AS (
    -- keep only the rows that belong to that month
    SELECT c.*
    FROM energy.energy_cost as c
    JOIN latest_month as l on date_trunc ('month' , c."date") = l.month_start
),

monthly_by_type AS (
    -- Step 3: one row per energy type (consumption and cost of the month)
    SELECT energy_type, sum(consumption) AS total_consumption
    ,sum(cost) as total_cost
    ,round(AVG(consumption),2) as avg_consumption_per_building
    FROM current_month_data 
    GROUP BY energy_type
)
-- Step 4: add the month info and the share of each type from the month's total cost
SELECT
    l.month_start::date as month_start,
    TO_CHAR(l.month_start, 'FMMonth YYYY')  AS month_label,
    m.energy_type,
    m.total_consumption,
    m.avg_consumption_per_building,
    round(m.total_cost::NUMERIC,2) as total_cost,
    round((m.total_cost / sum(m.total_cost) OVER () * 100)::NUMERIC,2) as cost_share_pct
FROM monthly_by_type m
CROSS JOIN latest_month l;

-- Show the result
SELECT * FROM energy.monthly_energy_summary;


-- View: dataset_calendar
-- One row per day between the first and the last date in the dataset (dynamic).
CREATE OR REPLACE VIEW energy.dataset_calendar AS
WITH date_range AS (
-- first and last date in the data (one row only)
                SELECT MIN(date) as first_date, MAX(date) as last_date
            FROM energy.energy_consumption
)
SELECT 
        d::date as date,
        EXTRACT(YEAR from d)::INT  as YEAR,
        EXTRACT(Month from d)::INT  as Month,
        EXTRACT(day from d)::INT  as day,
    TO_CHAR(d, 'FMMonth')           AS month_name,
    TO_CHAR(d, 'FMDay')             AS day_name
from date_range as r
CROSS JOIN generate_series (
        r.first_date::TIMESTAMP,
        r.last_date::TIMESTAMP,
        INTERVAL '1 day'
) as d;

-- Show the result
SELECT * FROM energy.dataset_calendar;

SELECT COUNT(*) FROM energy.dataset_calendar;


---Thank you ENG.Amr Ayyad for your Support---