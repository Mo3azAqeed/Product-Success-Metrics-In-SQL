
                                       /*Product(websites) Metrics Succes */


--1 Exposure: The count of users who successfully complete a jump onto the platform
WITH Exposure AS (
    SELECT
        TO_CHAR(session_begins, 'Q-YYYY') AS "The Quarter",
         COUNT(DISTINCT CASE WHEN user_id IS NULL THEN session_id ELSE NULL END) AS "Number Of people Exposure To The Product"
    FROM 
        session_summaries
    GROUP BY
        TO_CHAR(session_begins, 'Q-YYYY')
)
SELECT 
    "The Quarter",
    "Number Of people Exposure To The Product",
    (CASE 
        WHEN LAG("Number Of people Exposure To The Product") OVER (ORDER BY RIGHT("The Quarter", 4), LEFT("The Quarter", 1)) <> 0 THEN
            ("Number Of people Exposure To The Product" * 1.0 / LAG("Number Of people Exposure To The Product") OVER (ORDER BY RIGHT("The Quarter", 4), LEFT("The Quarter", 1)) - 1) * 100
        ELSE
            0
    END)  AS "Percentage Growth"
FROM
    Exposure;



--2 On boarding:it's when the First The customer Signed up To Your 
WITH Exposure AS (
    SELECT
        TO_CHAR(session_begins, 'Q-YYYY') AS "The Quarter",
        COUNT(DISTINCT CASE WHEN user_id IS NULL THEN session_id ELSE NULL END) AS "Number Of people Exposure To The Product"
    FROM 
        session_summaries
    GROUP BY
        "The Quarter"
),
Signing_up AS (
    SELECT 	
        TO_CHAR(created_at, 'Q-YYYY') AS "The Quarter",
        COUNT(DISTINCT user_id) AS "Number Of people Who signed Up",
		(COUNT(DISTINCT user_id)*1.0/(SELECT COUNT(DISTINCT user_id) FROM users))*100.0 AS "Quarter Contribuation Percentage"
    FROM
        users
    GROUP BY 
        "The Quarter"
)
SELECT 
    e."The Quarter",
    s."Number Of people Who signed Up",
    ((s."Number Of people Who signed Up" * 1.0) / e."Number Of people Exposure To The Product")*100.0 AS "Onboarding Rate",
	ROUND("Quarter Contribuation Percentage",2) As "Quarter Contribuation Percentage"
FROM
    Exposure AS e
JOIN 
    Signing_up AS s 
ON 
    e."The Quarter" = s."The Quarter"
ORDER BY 
    RIGHT(e."The Quarter",4),LEFT(e."The Quarter",1);


--3 Activations:it's when The Users First log in to his Account Afer The signing up
With Activation_sub AS
	(Select 
	u.user_id,
	u.created_at As "Signing up Date",
	MIN(session_begins) AS "The First Login After The Siging up",
	MAX(session_begins) AS "The Last Login",
	MAX(session_begins)- u.created_at AS "The Activation Time",
	COUNT(DISTINCT s.session_id) As "Number OF Visits"
FROM 
	session_summaries as s
JOIN 
	users AS u
ON 
	u.user_id=s.user_id
GROUP BY 
	u.user_id
),

activation_stat As
(
	SELECT	
		MIN("The Activation Time") AS "Minimum Duration",
 		PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY "The Activation Time") AS "1st Quartile",
    	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY "The Activation Time") AS "Median",
 		PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY "The Activation Time") AS "3rd Quartile",
    	MAX("The Activation Time") AS "Maximum Duration",
		TO_CHAR(MODE() WITHIN GROUP (ORDER BY "The Activation Time"),'HH24 "hours" MI "minutes" SS "seconds"') AS "The Mode",
		AVG("The Activation Time") AS "The Average Duration",
		 STDDEV(EXTRACT('day' FROM "The Activation Time")) AS "The Standard Deviation"
	FROM
		Activation_sub
),
buckets_cte AS (
    SELECT 
        WIDTH_BUCKET(EXTRACT('day' FROM "The Activation Time")::NUMERIC, 
                     (SELECT MIN(EXTRACT('day' FROM "The Activation Time")) FROM Activation_sub)::NUMERIC, 
                     (SELECT MAX(EXTRACT('day' FROM "The Activation Time")) FROM Activation_sub)::NUMERIC, 
                     15) AS bucket_number
    FROM 
        Activation_sub
)
SELECT 
    bucket_number,
    COUNT(*) AS frequency
FROM 
    buckets_cte
GROUP BY 
    bucket_number
ORDER BY 
    bucket_number;

--Monthly Active Users
SELECT 
	ROUND((COUNT(DISTINCT a.user_id)*1.00/(SELECT COUNT(DISTINCT user_id) FROM users))*100.0,2) AS "Monthly Active User"
FROM 
	session_summaries as a
INNER JOIN 
	session_summaries as b
ON 
	a.user_id=b.user_id
AND 
	b.session_begins <= a.session_begins + INTERVAL '30 days'
AND
	a.session_id <> b.session_id
AND
	EXTRACT('day' from a.session_begins) <> EXTRACT('day' from b.session_begins)
	

--4 Engagement;it's the time where The User Is purchasing /Viewing  A Product
--Initially Let's Say it's When he Placed His First Order is your Activat
--To Make it More Specific Let's Say Thos who placed And Complete  At Least One Order And loged In in The Last Month  Are The Real Active Users
WITH Activation_sub AS (
    SELECT 
        u.user_id,
        u.created_at AS "Signing up Date",
        MIN(s.session_begins) AS "The First Login After The Signing up",
        MAX(s.session_begins) AS "The Last Login",
        MAX(s.session_begins) - u.created_at AS "The Activation Time",
        COUNT(DISTINCT s.session_id) AS "Number OF Visits"
    FROM 
        session_summaries AS s
    JOIN 
        users AS u
    ON 
        u.user_id = s.user_id
    GROUP BY 
        u.user_id
),
Users_With_orders AS (
    SELECT 
        DISTINCT user_id 
    FROM 
        orders
    WHERE
        status NOT IN ('Cancelled', 'Returned')
)
SELECT 
  ROUND(((COUNT(DISTINCT a.user_id)*1.0)/(SELECT COUNT(DISTINCT user_id) FROM Activation_sub WHERE   NOW() >= "The Last Login" + INTERVAL '90 days'))*100.0,2) || '%' AS "The highley Engagement Users"
FROM 
    Activation_sub AS a 
INNER JOIN
    Users_With_orders AS u
ON
    u.user_id= a.user_id 
WHERE 
   a."The Last Login" >= CURRENT_DATE  - INTERVAL '180 days'
AND  "Number OF Visits" >= 3;

--5 Retention

WITH CTE AS
(SELECT  
	user_id,
	session_id,
	session_begins- FIRST_VALUE(session_begins) OVER(PARTITION BY user_id ORDER BY session_begins) AS "The Difference Since The Fisrt Login",
	 LAST_VALUE(session_begins) OVER(PARTITION BY user_id ORDER BY session_begins) AS "The Last Login",
	COALESCE(EXTRACT('day' FROM session_begins-LAG(session_begins) OVER(PARTITION BY user_id ORDER BY session_begins)),0) AS "The Difference In Days since The Last Visit"
FROM 
	session_summaries),
retain As 
(SELECT 
		user_id AS "Retrained",
		COUNT(*) AS "Number of Visits",
		MAX("The Difference In Days since The Last Visit") AS "The Longest Duration Of Absence",
		MAX("The Difference Since The Fisrt Login") AS "Duration OF Rentation"
FROM
	CTE 
WHERE 
	"The Last Login" >= CURRENT_DATE  - INTERVAL '180 days'
GROUP BY 
	user_id
HAVING 	
	COUNT(*) > 1
	AND
	MAX("The Difference In Days since The Last Visit") > 0 
),
Activation_sub AS (
    SELECT 
        u.user_id,
        u.created_at AS "Signing up Date",
        MIN(s.session_begins) AS "The First Login After The Signing up",
        MAX(s.session_begins) AS "The Last Login",
        MAX(s.session_begins) - u.created_at AS "The Activation Time",
        COUNT(DISTINCT s.session_id) AS "Number OF Visits"
    FROM 
        session_summaries AS s
    JOIN 
        users AS u
    ON 
        u.user_id = s.user_id
    GROUP BY 
        u.user_id
) 
SELECT	
	ROUND((COUNT(DISTINCT "Retrained" )*1.0) / (SELECT COUNT(DISTINCT user_id) FROM Activation_sub WHERE NOW() >= "The Last Login" + INTERVAL '90 days') * 100, 2) || ' %' AS "Percentage OF Retrained Users"
FROM
	retain

