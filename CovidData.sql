USE CovidProject;

-- Creating cleaner tables from raw imported data, since it was annoying to work with the latter.
-- Note: FLOAT is used instead of BIGINT due to the numerous division operations to be used in the queries. BIGINT will not return values with decimal places.

DROP TABLE IF EXISTS ..base;
CREATE TABLE base
(
country NVARCHAR(51),
date DATETIME,
code NVARCHAR(9),
continent NVARCHAR(13),
population FLOAT,
new_cases FLOAT,
total_cases FLOAT
CONSTRAINT basekey PRIMARY KEY (country, date)
)

INSERT INTO ..base
SELECT country, date, code, continent, population, new_cases, total_cases
FROM ..deaths;

DROP TABLE IF EXISTS ..dths
CREATE TABLE dths
(
country NVARCHAR(51),
date DATETIME,
new_dths FLOAT,
total_dths FLOAT,
CONSTRAINT dthskey PRIMARY KEY (country, date)
)

INSERT INTO ..dths
SELECT country, date, new_deaths, total_deaths
FROM ..deaths

DROP TABLE IF EXISTS ..vacs
CREATE TABLE vacs
(
country NVARCHAR(51),
date DATETIME,
new_vacs FLOAT,
total_vacs FLOAT,
CONSTRAINT vacskey PRIMARY KEY (country, date)
)

INSERT INTO ..vacs
SELECT country, date, new_vaccinations, total_vaccinations
FROM ..vaccinations

-- Now creating appropriate queries and views from cleaner tables. 
-- Note: CREATE VIEW commands need to be executed individually not in batch.

-- View: Calculate Mortality Rate as percentage.
-- 0 cannot be divided, so if total_cases is 0, it is converted to NULL.
-- NULL is not a valid mortality rate, so it is converted back to 0 after division.
-- The quotient is multiplied by 100 to arrive at the percentage.
-- The result is rounded for readability.
-- FLOAT is used instead of DECIMAL due to division results varying too much.

DROP VIEW IF EXISTS MaxMortalityRate

CREATE VIEW MaxMortalityRate AS
SELECT base.country, base.date, population, total_cases, total_dths, ROUND(COALESCE(total_dths/NULLIF(total_cases, 0), 0)*100, 2) AS mortality_rate
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date

--SELECT * FROM ..MaxMortalityRate ORDER BY 1, 2;

-- View: Infected Rate as Percentage per Country
-- Calculate percentage of population that has previously caught COVID. 
-- This is a rough calculation that doesn't account for unfortunates who have had it multiple times.

DROP VIEW IF EXISTS InfectedRate

CREATE VIEW InfectedRate AS
SELECT base.country, base.date, population, total_cases, ROUND((total_cases/population)*100, 3) AS infected_rate
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date

--SELECT * FROM ..InfectedRate ORDER BY 1, 2;

-- View: Peak number of Cases per Country. Roughly indicates how many in that country are known to have caught Covid. Doesn't account for bad reporting or repeat infections.
-- Note: The query also shows date, selecting by the earliest date when cases aren't updated daily. This isn't useful but could be used if it was used on active cases data.

DROP VIEW IF EXISTS PeakInfectedRate

CREATE VIEW PeakInfectedRate AS
SELECT base_a.country, base_a.population, MIN(date) as date, max_cases, ROUND((max_cases/base_a.population)*100, 3) AS infected_rate
FROM ..base AS base_a
JOIN
(SELECT country, population, MAX(total_cases) AS max_cases
FROM ..base
GROUP BY country, population) AS base_b
ON base_a.country = base_b.country AND base_a.population = base_b.population AND base_a.total_cases = base_b.max_cases
GROUP BY base_a.country, base_a.population, max_cases

--SELECT * FROM PeakInfectedRate ORDER BY 1, 2;

-- View: Total Deaths per Country over time.
-- Find the highest number for each country, then group the rows by country.

DROP VIEW IF EXISTS TotalDeathsOverTime

CREATE VIEW TotalDeathsOverTime AS
SELECT base.country, MAX(total_dths) AS total_dths
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date
WHERE continent IS NOT NULL
GROUP BY base.country

--SELECT * FROM TotalDeathsOverTime ORDER BY 2;

-- View: Total Deaths per Region over time.

DROP VIEW IF EXISTS RegionTotalDeathsOverTime

CREATE VIEW RegionTotalDeathsOverTime AS
SELECT country, MAX(total_deaths) AS total_deaths
FROM ..deaths
WHERE continent IS NULL AND total_deaths IS NOT NULL
GROUP BY country;

--SELECT * FROM ..RegionTotalDeathsOverTime ORDER BY 1, 2

-- View: Total Deaths per Continent over time.

DROP VIEW IF EXISTS ContinentTotalDeathsOverTime

CREATE VIEW ContinentTotalDeathsOverTime AS
SELECT base.continent, MAX(total_dths) AS total_dths
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date
WHERE continent IS NOT NULL AND total_dths IS NOT NULL
GROUP BY base.continent

--SELECT * FROM ContinentTotalDeathsOverTime ORDER BY 2;

-- View: Total cases, deaths, and mortaliry rate for countries in aggregate. This may be skewed by the irregularity in reporting by many countries.
-- Note: Mortality rate calculation is unsophisticated, as it compares to the new cases of that same day which is obviously absurd.

DROP VIEW IF EXISTS CountryFinalCasesDeathsMortality

CREATE VIEW CountryFinalCasesDeathsMortality AS
SELECT base.country, MAX(total_cases) AS total_cases, MAX(total_dths) AS total_dths, ROUND(COALESCE(MAX(total_dths)/NULLIF(MAX(total_cases), 0), 0)*100, 2) as mortality_rate
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date
WHERE continent IS NOT NULL
GROUP BY base.country

SELECT * FROM CountryFinalCasesDeathsMortality

-- View: New cases, deaths, and daily mortality rate for the globe in aggregate. This may be skewed by the irregularity in reporting by many countries.
-- Note: Mortality rate calculation is unsophisticated, as per previous explanation.

DROP VIEW IF EXISTS GlobalCasesDeathsMortality

CREATE VIEW GlobalCasesDeathsMortality AS
SELECT base.date, SUM(new_cases) as daily_cases, SUM(new_dths) as daily_dths, ROUND(COALESCE(SUM(new_dths)/NULLIF(SUM(new_cases), 0), 0)*100, 2) as daily_mortality_rate
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date
WHERE continent IS NOT NULL
GROUP BY base.date

--SELECT * FROM GlobalCasesDeathsMortality ORDER BY 1, 2;

-- View: Final count of total cases, deaths around the globe in aggregate, and mortality rate. This uses 

DROP VIEW IF EXISTS GlobalFinalCasesDeathsMortality

CREATE VIEW GlobalFinalCasesDeathsMortality AS
SELECT SUM(total_cases) AS total_cases, SUM(total_dths) AS total_dths, ROUND(COALESCE(SUM(total_dths)/NULLIF(SUM(total_cases), 0), 0)*100, 2) as mortality_rate
FROM
(SELECT base.country, MAX(total_cases) AS total_cases, MAX(total_dths) AS total_dths
FROM ..base
JOIN ..dths
ON base.country = dths.country AND base.date = dths.date
WHERE continent IS NOT NULL
GROUP BY base.country) AS base_a

-- View: Alternate for previous view using another view instead of subquery.

CREATE VIEW GlobalFinalCasesDeathsMortality AS
SELECT SUM(total_cases) AS total_cases, SUM(total_dths) AS total_dths, ROUND(COALESCE(SUM(total_dths)/NULLIF(SUM(total_cases), 0), 0)*100, 2) as mortality_rate
FROM
CountryFinalCasesDeathsMortality

--SELECT * FROM GlobalFinalCasesDeathsMortality;

-- View: A rolling count of vaccinations across time, per country

DROP VIEW IF EXISTS CountryVacsRollingCount

CREATE VIEW CountryVacsRollingCount AS
SELECT base.continent, base.country, base.date, base.population, vacs.new_vacs, 
	SUM(new_vacs) OVER (PARTITION BY base.country ORDER BY base.country, base.date) AS vacs_count
FROM ..base
JOIN ..vacs
ON base.country = vacs.country AND base.date = vacs.date
WHERE base.continent IS NOT NULL AND new_vacs IS NOT NULL

SELECT * FROM CountryVacsRollingCount ORDER BY 1, 2, 3

-- View: Using previous rolling count, also calculate the proportion of population vaccinated.
-- Note: This does not account for boosters, so percentage can go above 100%.

DROP VIEW IF EXISTS DailyPercentageVaccinated

CREATE VIEW DailyPercentageVaccinated AS
WITH vacs_proportion (continent, country, date, population, new_vaccinations, vacs_count)
AS
(SELECT base.continent, base.country, base.date, base.population, vacs.new_vacs, 
	SUM(new_vacs) OVER (PARTITION BY base.country ORDER BY base.country, base.date) AS vacs_count
FROM ..base
JOIN ..vacs
ON base.country = vacs.country AND base.date = vacs.date
WHERE base.continent IS NOT NULL AND new_vacs IS NOT NULL)
SELECT *, ROUND((vacs_count/population)*100, 2) AS vacs_percentage
FROM vacs_proportion

SELECT * FROM DailyPercentageVaccinated ORDER BY 2, 3;

-- View: Same as above, except referring to view.

DROP VIEW IF EXISTS DailyPercentageVaccinated

CREATE VIEW DailyPercentageVaccinated AS
SELECT *, ROUND((vacs_count/population)*100, 2) AS vacs_percentage
FROM CountryVacsRollingCount

SELECT * FROM DailyPercentageVaccinated ORDER BY 2, 3