/* =====================================================================
   TIMESHEET DATABASE  -  SUBQUERIES, VIEWS & STORED PROCEDURE  (MySQL 8.0+)
   Run timesheet_joins.sql first (Part A + Part B) so the tables and data exist.
   ===================================================================== */
USE timesheet_db;


/* =====================================================================
   PART 1 : THREE SUBQUERIES  (three different types)
   ===================================================================== */

-- ---------------------------------------------------------------------
-- SUBQUERY 1 : SCALAR SUBQUERY  (returns exactly one value)
-- Employees who earn more than the company-wide average hourly rate.
-- Teaching point: the inner query runs ONCE, returns a single number,
--                 and the outer query compares every row against it.
-- Expected: Rajesh Mehta, Priya Sharma, Amit Verma  (average is about 1086.92)
-- ---------------------------------------------------------------------
SELECT e.emp_id,
       CONCAT(e.first_name, ' ', e.last_name)          AS employee,
       e.hourly_rate,
       (SELECT ROUND(AVG(hourly_rate), 2) FROM employees) AS company_avg_rate   -- scalar subquery in SELECT
FROM employees e
WHERE e.hourly_rate > (SELECT AVG(hourly_rate) FROM employees)                  -- scalar subquery in WHERE
ORDER BY e.hourly_rate DESC;


-- ---------------------------------------------------------------------
-- SUBQUERY 2 : CORRELATED SUBQUERY  (inner query depends on the outer row)
-- Latest timesheet of every employee.
-- Teaching point: the inner query re-runs for EACH outer row because it uses ts.emp_id.
-- Expected: 9 rows, one per employee who has ever submitted a timesheet.
-- ---------------------------------------------------------------------
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       ts.week_start_date                     AS latest_week,
       ts.status
FROM timesheets ts
INNER JOIN employees e ON e.emp_id = ts.emp_id
WHERE ts.week_start_date = (SELECT MAX(t2.week_start_date)
                            FROM timesheets t2
                            WHERE t2.emp_id = ts.emp_id)       -- correlated with the outer query
ORDER BY employee;


-- ---------------------------------------------------------------------
-- SUBQUERY 3 : DERIVED TABLE (subquery in FROM) + NESTED SCALAR SUBQUERY
-- Projects whose total logged hours are above the average hours per project.
-- Teaching point: aggregate first in a derived table, then compare against
--                 an aggregate of that aggregate.
-- Expected: Retail Mobile App (59.5), Logistics Tracking Portal (59.5),
--           Patient Management System (44.0)   -  the average is 43.4
-- ---------------------------------------------------------------------
SELECT p.project_name,
       ph.total_hours
FROM projects p
INNER JOIN (SELECT t.project_id,
                   SUM(te.hours_worked) AS total_hours
            FROM tasks t
            INNER JOIN timesheet_entries te ON te.task_id = t.task_id
            GROUP BY t.project_id) ph                                  -- derived table
        ON ph.project_id = p.project_id
WHERE ph.total_hours > (SELECT AVG(x.total_hours)                      -- nested scalar subquery
                        FROM (SELECT SUM(te2.hours_worked) AS total_hours
                              FROM tasks t2
                              INNER JOIN timesheet_entries te2 ON te2.task_id = t2.task_id
                              GROUP BY t2.project_id) x)
ORDER BY ph.total_hours DESC;


/* =====================================================================
   PART 2 : COMPLEX VIEW
   vw_weekly_timesheet_summary  -  one row per employee per timesheet week.
   Combines 9 table references: timesheets, employees, designations, departments,
   employees (manager), employees (approver), plus two derived tables
   (hours/cost and leave overlap).
   ===================================================================== */
CREATE OR REPLACE VIEW vw_weekly_timesheet_summary AS
SELECT ts.timesheet_id,
       ts.week_start_date,
       DATE_ADD(ts.week_start_date, INTERVAL 6 DAY)               AS week_end_date,
       e.emp_id,
       CONCAT(e.first_name, ' ', e.last_name)                     AS employee,
       ds.title                                                   AS designation,
       COALESCE(d.dept_name, 'Not assigned')                      AS department,
       CONCAT(m.first_name, ' ', m.last_name)                     AS manager,
       ts.status                                                  AS timesheet_status,
       CONCAT(a.first_name, ' ', a.last_name)                     AS approved_by,
       COALESCE(h.total_hours, 0)                                 AS total_hours,
       COALESCE(h.billable_hours, 0)                              AS billable_hours,
       ROUND(COALESCE(h.billable_hours, 0)
             / NULLIF(h.total_hours, 0) * 100, 1)                 AS billable_pct,
       COALESCE(h.projects_worked, 0)                             AS projects_worked,
       COALESCE(h.labour_cost, 0)                                 AS labour_cost,
       COALESCE(lv.leave_days, 0)                                 AS leave_days,          -- calendar days of approved leave in the week
       40 - 8 * COALESCE(lv.leave_days, 0)                        AS expected_hours,
       ROUND(COALESCE(h.total_hours, 0)
             / NULLIF(40 - 8 * COALESCE(lv.leave_days, 0), 0) * 100, 1) AS utilisation_pct,
       CASE ts.status
            WHEN 'Draft'     THEN 'Not submitted'
            WHEN 'Submitted' THEN 'Awaiting approval'
            WHEN 'Rejected'  THEN 'Rejected - resubmit'
            ELSE 'OK'
       END                                                        AS action_flag
FROM timesheets ts
INNER JOIN employees    e  ON e.emp_id          = ts.emp_id
INNER JOIN designations ds ON ds.designation_id = e.designation_id
LEFT  JOIN departments  d  ON d.dept_id         = e.dept_id
LEFT  JOIN employees    m  ON m.emp_id          = e.manager_id
LEFT  JOIN employees    a  ON a.emp_id          = ts.approved_by
-- derived table 1: hours, billable hours, projects touched and cost per timesheet
LEFT  JOIN (SELECT te.timesheet_id,
                   SUM(te.hours_worked)                                              AS total_hours,
                   SUM(CASE WHEN te.is_billable = 1 THEN te.hours_worked ELSE 0 END) AS billable_hours,
                   COUNT(DISTINCT t.project_id)                                      AS projects_worked,
                   SUM(te.hours_worked * e2.hourly_rate)                             AS labour_cost
            FROM timesheet_entries te
            INNER JOIN tasks      t   ON t.task_id       = te.task_id
            INNER JOIN timesheets ts2 ON ts2.timesheet_id = te.timesheet_id
            INNER JOIN employees  e2  ON e2.emp_id        = ts2.emp_id
            GROUP BY te.timesheet_id) h
        ON h.timesheet_id = ts.timesheet_id
-- derived table 2: approved leave days overlapping each timesheet week (non-equi join)
LEFT  JOIN (SELECT ts3.timesheet_id,
                   SUM(DATEDIFF(LEAST(lr.to_date,   DATE_ADD(ts3.week_start_date, INTERVAL 6 DAY)),
                                GREATEST(lr.from_date, ts3.week_start_date)) + 1) AS leave_days
            FROM timesheets ts3
            INNER JOIN leave_requests lr
                    ON lr.emp_id    = ts3.emp_id
                   AND lr.status    = 'Approved'
                   AND lr.from_date <= DATE_ADD(ts3.week_start_date, INTERVAL 6 DAY)
                   AND lr.to_date   >= ts3.week_start_date
            GROUP BY ts3.timesheet_id) lv
        ON lv.timesheet_id = ts.timesheet_id;

-- Using the complex view like a normal table -------------------------------

-- Everything for one week
SELECT * FROM vw_weekly_timesheet_summary
WHERE week_start_date = '2026-09-28'
ORDER BY total_hours DESC;

-- Timesheets that need action, with the manager to chase
SELECT employee, week_start_date, timesheet_status, action_flag, manager
FROM vw_weekly_timesheet_summary
WHERE action_flag <> 'OK'
ORDER BY week_start_date, manager;

-- Department roll-up built ON TOP of the view (view + GROUP BY)
SELECT department,
       COUNT(*)                   AS timesheets,
       SUM(total_hours)           AS total_hours,
       ROUND(AVG(utilisation_pct), 1) AS avg_utilisation_pct,
       SUM(labour_cost)           AS labour_cost
FROM vw_weekly_timesheet_summary
GROUP BY department
ORDER BY total_hours DESC;


/* =====================================================================
   PART 3 : VIEW + STORED PROCEDURE
   Step 1: a simple "flattened" view that hides the 7-table join.
   Step 2: a stored procedure that reads from that view.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 3a. vw_timesheet_detail : one row per timesheet entry, fully described
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_timesheet_detail AS
SELECT te.entry_id,
       te.work_date,
       ts.week_start_date,
       ts.status                                  AS timesheet_status,
       e.emp_id,
       CONCAT(e.first_name, ' ', e.last_name)     AS employee,
       COALESCE(d.dept_name, 'Not assigned')      AS department,
       COALESCE(c.client_name, 'Internal')        AS client_name,
       p.project_id,
       p.project_name,
       t.task_name,
       te.hours_worked,
       te.is_billable,
       e.hourly_rate,
       te.hours_worked * e.hourly_rate            AS cost,
       te.description
FROM timesheet_entries te
INNER JOIN timesheets  ts ON ts.timesheet_id = te.timesheet_id
INNER JOIN employees   e  ON e.emp_id        = ts.emp_id
LEFT  JOIN departments d  ON d.dept_id       = e.dept_id
INNER JOIN tasks       t  ON t.task_id       = te.task_id
INNER JOIN projects    p  ON p.project_id    = t.project_id
LEFT  JOIN clients     c  ON c.client_id     = p.client_id;

-- Students can now query seven tables with one simple statement:
SELECT * FROM vw_timesheet_detail WHERE project_name = 'Retail Mobile App' ORDER BY work_date;


-- ---------------------------------------------------------------------
-- 3b. sp_employee_timesheet_report(emp_id, from_date, to_date)
--     Returns 3 result sets:  (1) employee header
--                             (2) day-by-day entries
--                             (3) project-wise summary
--     Includes input validation with SIGNAL (custom error messages).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_employee_timesheet_report;

DELIMITER $$

CREATE PROCEDURE sp_employee_timesheet_report (
    IN p_emp_id    INT,
    IN p_from_date DATE,
    IN p_to_date   DATE
)
BEGIN
    -- validation 1: employee must exist
    IF NOT EXISTS (SELECT 1 FROM employees WHERE emp_id = p_emp_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Employee not found';
    END IF;

    -- validation 2: date range must be valid
    IF p_from_date > p_to_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'From date cannot be after To date';
    END IF;

    -- result set 1: employee header
    SELECT e.emp_id,
           CONCAT(e.first_name, ' ', e.last_name) AS employee,
           ds.title                               AS designation,
           COALESCE(d.dept_name, 'Not assigned')  AS department,
           CONCAT(m.first_name, ' ', m.last_name) AS manager,
           p_from_date                            AS report_from,
           p_to_date                              AS report_to
    FROM employees e
    INNER JOIN designations ds ON ds.designation_id = e.designation_id
    LEFT  JOIN departments  d  ON d.dept_id         = e.dept_id
    LEFT  JOIN employees    m  ON m.emp_id          = e.manager_id
    WHERE e.emp_id = p_emp_id;

    -- result set 2: day-by-day detail (from the view)
    SELECT work_date,
           project_name,
           task_name,
           hours_worked,
           IF(is_billable = 1, 'Yes', 'No') AS billable,
           cost,
           timesheet_status
    FROM vw_timesheet_detail
    WHERE emp_id = p_emp_id
      AND work_date BETWEEN p_from_date AND p_to_date
    ORDER BY work_date, project_name;

    -- result set 3: project-wise summary (from the view)
    SELECT project_name,
           client_name,
           SUM(hours_worked)                                              AS total_hours,
           SUM(CASE WHEN is_billable = 1 THEN hours_worked ELSE 0 END)    AS billable_hours,
           SUM(cost)                                                      AS total_cost
    FROM vw_timesheet_detail
    WHERE emp_id = p_emp_id
      AND work_date BETWEEN p_from_date AND p_to_date
    GROUP BY project_id, project_name, client_name
    ORDER BY total_hours DESC;
END$$

DELIMITER ;

-- Try it -----------------------------------------------------------------
CALL sp_employee_timesheet_report(3, '2026-09-21', '2026-09-30');   -- Amit Verma, both weeks
CALL sp_employee_timesheet_report(5, '2026-09-28', '2026-09-30');   -- Rohan Das (includes the unassigned-project entry)
CALL sp_employee_timesheet_report(1, '2026-09-21', '2026-09-30');   -- Rajesh: header only, no entries
CALL sp_employee_timesheet_report(99, '2026-09-21', '2026-09-30');  -- error: Employee not found
CALL sp_employee_timesheet_report(3, '2026-09-30', '2026-09-21');   -- error: From date cannot be after To date

/* ===================== END OF SCRIPT ===================== */
