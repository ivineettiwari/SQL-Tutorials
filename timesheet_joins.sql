/* =====================================================================
   TIMESHEET DATABASE  -  SQL JOINS TRAINING KIT   (MySQL 8.0+)
   =====================================================================
   11 tables:
     1. departments          7. project_assignments  (employee <-> project, M:N)
     2. designations         8. timesheets           (one per employee per week)
     3. employees            9. timesheet_entries    (daily hours against a task)
     4. clients             10. leave_types
     5. projects            11. leave_requests
     6. tasks

   Relationships (parent <- child):
     departments  <- employees, projects
     designations <- employees
     employees    <- employees (manager_id, SELF reference), timesheets,
                     project_assignments, leave_requests, timesheets.approved_by
     clients      <- projects
     projects     <- tasks, project_assignments
     tasks        <- timesheet_entries
     timesheets   <- timesheet_entries
     leave_types  <- leave_requests

   Deliberate "gaps" in the data (so LEFT / RIGHT / anti joins have something to show):
     - Department 'Legal' has no employees
     - Employee 'Sanjay Gupta' has no department (NULL)
     - Client 'Orbit Telecom' has no projects
     - Project 'Internal HR Portal' has no client and no tasks
     - 7 tasks have no time logged
     - Employees 1, 8, 9, 12 never submitted a timesheet
     - Employee 5 logged time on a project he is not assigned to
     - Employee 6 logged time on a day she was on approved leave
   ===================================================================== */


/* ---------------------------------------------------------------------
   PART A : DATABASE + TABLES
   --------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS timesheet_db;
USE timesheet_db;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS timesheet_entries;
DROP TABLE IF EXISTS timesheets;
DROP TABLE IF EXISTS leave_requests;
DROP TABLE IF EXISTS leave_types;
DROP TABLE IF EXISTS project_assignments;
DROP TABLE IF EXISTS tasks;
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS clients;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS designations;
DROP TABLE IF EXISTS departments;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE departments (
    dept_id    INT AUTO_INCREMENT PRIMARY KEY,
    dept_name  VARCHAR(50)  NOT NULL UNIQUE,
    location   VARCHAR(50)
);

CREATE TABLE designations (
    designation_id  INT AUTO_INCREMENT PRIMARY KEY,
    title           VARCHAR(50) NOT NULL UNIQUE,
    grade_level     INT NOT NULL
);

CREATE TABLE employees (
    emp_id          INT AUTO_INCREMENT PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(100) NOT NULL UNIQUE,
    dept_id         INT NULL,                       -- NULL allowed (demo for LEFT JOIN)
    designation_id  INT NOT NULL,
    manager_id      INT NULL,                       -- self reference
    hire_date       DATE NOT NULL,
    hourly_rate     DECIMAL(8,2) NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'Active',
    FOREIGN KEY (dept_id)        REFERENCES departments(dept_id),
    FOREIGN KEY (designation_id) REFERENCES designations(designation_id),
    FOREIGN KEY (manager_id)     REFERENCES employees(emp_id)
);

CREATE TABLE clients (
    client_id    INT AUTO_INCREMENT PRIMARY KEY,
    client_name  VARCHAR(100) NOT NULL,
    country      VARCHAR(50)
);

CREATE TABLE projects (
    project_id    INT AUTO_INCREMENT PRIMARY KEY,
    project_name  VARCHAR(100) NOT NULL,
    client_id     INT NULL,                         -- NULL = internal project
    dept_id       INT NOT NULL,                     -- owning department
    start_date    DATE NOT NULL,
    end_date      DATE NULL,
    budget        DECIMAL(12,2) NOT NULL,
    status        VARCHAR(15) NOT NULL,
    FOREIGN KEY (client_id) REFERENCES clients(client_id),
    FOREIGN KEY (dept_id)   REFERENCES departments(dept_id)
);

CREATE TABLE tasks (
    task_id          INT AUTO_INCREMENT PRIMARY KEY,
    project_id       INT NOT NULL,
    task_name        VARCHAR(100) NOT NULL,
    estimated_hours  DECIMAL(6,2) NOT NULL,
    status           VARCHAR(15) NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE project_assignments (
    assignment_id     INT AUTO_INCREMENT PRIMARY KEY,
    project_id        INT NOT NULL,
    emp_id            INT NOT NULL,
    role_on_project   VARCHAR(30) NOT NULL,
    assigned_date     DATE NOT NULL,
    UNIQUE (project_id, emp_id),
    FOREIGN KEY (project_id) REFERENCES projects(project_id),
    FOREIGN KEY (emp_id)     REFERENCES employees(emp_id)
);

CREATE TABLE timesheets (
    timesheet_id    INT AUTO_INCREMENT PRIMARY KEY,
    emp_id          INT NOT NULL,
    week_start_date DATE NOT NULL,                  -- Monday
    status          VARCHAR(15) NOT NULL,           -- Draft / Submitted / Approved / Rejected
    approved_by     INT NULL,
    UNIQUE (emp_id, week_start_date),
    FOREIGN KEY (emp_id)      REFERENCES employees(emp_id),
    FOREIGN KEY (approved_by) REFERENCES employees(emp_id)
);

CREATE TABLE timesheet_entries (
    entry_id      INT AUTO_INCREMENT PRIMARY KEY,
    timesheet_id  INT NOT NULL,
    task_id       INT NOT NULL,
    work_date     DATE NOT NULL,
    hours_worked  DECIMAL(4,2) NOT NULL CHECK (hours_worked > 0 AND hours_worked <= 24),
    is_billable   TINYINT(1) NOT NULL DEFAULT 1,
    description   VARCHAR(200),
    FOREIGN KEY (timesheet_id) REFERENCES timesheets(timesheet_id),
    FOREIGN KEY (task_id)      REFERENCES tasks(task_id)
);

CREATE TABLE leave_types (
    leave_type_id  INT AUTO_INCREMENT PRIMARY KEY,
    leave_name     VARCHAR(30) NOT NULL UNIQUE,
    annual_quota   INT NOT NULL
);

CREATE TABLE leave_requests (
    leave_id       INT AUTO_INCREMENT PRIMARY KEY,
    emp_id         INT NOT NULL,
    leave_type_id  INT NOT NULL,
    from_date      DATE NOT NULL,
    to_date        DATE NOT NULL,
    days_taken     DECIMAL(4,1) NOT NULL,
    status         VARCHAR(15) NOT NULL,            -- Pending / Approved / Rejected
    FOREIGN KEY (emp_id)        REFERENCES employees(emp_id),
    FOREIGN KEY (leave_type_id) REFERENCES leave_types(leave_type_id)
);


/* ---------------------------------------------------------------------
   PART B : SAMPLE DATA
   --------------------------------------------------------------------- */
INSERT INTO departments (dept_id, dept_name, location) VALUES
(1, 'Engineering',       'Pune'),
(2, 'Quality Assurance', 'Pune'),
(3, 'Human Resources',   'Mumbai'),
(4, 'Finance',           'Mumbai'),
(5, 'Marketing',         'Bengaluru'),
(6, 'Legal',             'Delhi');                  -- no employees

INSERT INTO designations (designation_id, title, grade_level) VALUES
(1, 'CEO',                  5),
(2, 'Engineering Manager',  4),
(3, 'Senior Developer',     3),
(4, 'Developer',            2),
(5, 'QA Engineer',          2),
(6, 'HR Executive',         2),
(7, 'Accountant',           2),
(8, 'Marketing Executive',  2),
(9, 'Intern',               1);

-- managers are inserted before their reports (self-referencing FK)
INSERT INTO employees
(emp_id, first_name, last_name, email, dept_id, designation_id, manager_id, hire_date, hourly_rate, status) VALUES
( 1, 'Rajesh', 'Mehta',    'rajesh.mehta@acme.com',    1, 1, NULL, '2018-01-10', 2500.00, 'Active'),
( 2, 'Priya',  'Sharma',   'priya.sharma@acme.com',    1, 2, 1,    '2019-03-15', 1800.00, 'Active'),
( 3, 'Amit',   'Verma',    'amit.verma@acme.com',      1, 3, 2,    '2020-06-01', 1400.00, 'Active'),
( 4, 'Sneha',  'Iyer',     'sneha.iyer@acme.com',      1, 4, 2,    '2021-08-20', 1000.00, 'Active'),
( 5, 'Rohan',  'Das',      'rohan.das@acme.com',       1, 4, 3,    '2022-01-17',  950.00, 'Active'),
( 6, 'Neha',   'Kapoor',   'neha.kapoor@acme.com',     2, 5, 2,    '2021-02-11',  900.00, 'Active'),
( 7, 'Karan',  'Singh',    'karan.singh@acme.com',     2, 5, 2,    '2022-07-04',  850.00, 'Active'),
( 8, 'Anjali', 'Nair',     'anjali.nair@acme.com',     3, 6, 1,    '2020-09-09',  800.00, 'Active'),
( 9, 'Vikram', 'Joshi',    'vikram.joshi@acme.com',    4, 7, 1,    '2019-11-25',  850.00, 'Active'),
(10, 'Pooja',  'Reddy',    'pooja.reddy@acme.com',     5, 8, 1,    '2021-05-18',  800.00, 'Active'),
(11, 'Arjun',  'Patel',    'arjun.patel@acme.com',     1, 9, 3,    '2024-06-03',  400.00, 'Active'),
(12, 'Meera',  'Kulkarni', 'meera.kulkarni@acme.com',  2, 5, 2,    '2023-03-13',  880.00, 'Inactive'),
(13, 'Sanjay', 'Gupta',    'sanjay.gupta@acme.com',    NULL, 4, 2, '2023-10-02', 1000.00, 'Active');   -- no department

INSERT INTO clients (client_id, client_name, country) VALUES
(1, 'Apex Retail',        'India'),
(2, 'BlueWave Logistics', 'USA'),
(3, 'Sunrise Health',     'UK'),
(4, 'GreenLeaf Foods',    'India'),
(5, 'Orbit Telecom',      'Singapore');             -- no projects

INSERT INTO projects (project_id, project_name, client_id, dept_id, start_date, end_date, budget, status) VALUES
(1, 'Retail Mobile App',          1,    1, '2026-01-05', '2026-09-30', 1500000.00, 'Active'),
(2, 'Logistics Tracking Portal',  2,    1, '2026-02-01', '2026-12-31', 2500000.00, 'Active'),
(3, 'Patient Management System',  3,    1, '2026-03-10', NULL,         1800000.00, 'Active'),
(4, 'Retail App QA Automation',   1,    2, '2026-04-01', '2026-10-31',  600000.00, 'Active'),
(5, 'Food Ordering Website',      4,    1, '2025-06-01', '2026-01-31',  900000.00, 'Completed'),
(6, 'Brand Campaign Dashboard',   4,    5, '2026-05-01', '2026-11-30',  500000.00, 'Active'),
(7, 'Internal HR Portal',         NULL, 3, '2026-06-01', '2026-12-15',  300000.00, 'Planned');   -- internal, no tasks

INSERT INTO tasks (task_id, project_id, task_name, estimated_hours, status) VALUES
( 1, 1, 'UI Design',             80.00, 'Completed'),
( 2, 1, 'Backend API',          160.00, 'In Progress'),
( 3, 1, 'Payment Integration',  100.00, 'In Progress'),
( 4, 2, 'Requirement Analysis',  40.00, 'Completed'),
( 5, 2, 'Tracking Module',      200.00, 'In Progress'),
( 6, 2, 'Dashboard Reports',    120.00, 'Not Started'),
( 7, 3, 'Database Design',       60.00, 'Completed'),
( 8, 3, 'Patient Module',       180.00, 'In Progress'),
( 9, 4, 'Test Plan',             50.00, 'Completed'),
(10, 4, 'Automation Scripts',   150.00, 'In Progress'),
(11, 5, 'Frontend Build',       120.00, 'Completed'),
(12, 5, 'Deployment',            30.00, 'Completed'),
(13, 6, 'Campaign Analytics',    90.00, 'In Progress'),
(14, 6, 'Data Visualization',    70.00, 'Not Started'),
(15, 1, 'Bug Fixing',            60.00, 'In Progress');

INSERT INTO project_assignments (assignment_id, project_id, emp_id, role_on_project, assigned_date) VALUES
( 1, 1,  2, 'Project Manager', '2026-01-05'),
( 2, 1,  3, 'Tech Lead',       '2026-01-05'),
( 3, 1,  4, 'Developer',       '2026-01-10'),
( 4, 1, 11, 'Developer',       '2026-06-03'),
( 5, 2,  2, 'Project Manager', '2026-02-01'),
( 6, 2,  3, 'Tech Lead',       '2026-02-01'),
( 7, 2,  5, 'Developer',       '2026-02-05'),
( 8, 2, 13, 'Developer',       '2026-02-05'),
( 9, 3,  2, 'Project Manager', '2026-03-10'),
(10, 3,  4, 'Developer',       '2026-03-12'),
(11, 3,  5, 'Developer',       '2026-03-12'),
(12, 4,  6, 'Project Manager', '2026-04-01'),
(13, 4,  7, 'QA Engineer',     '2026-04-01'),
(14, 4, 12, 'QA Engineer',     '2026-04-01'),
(15, 5,  3, 'Tech Lead',       '2025-06-01'),
(16, 5,  4, 'Developer',       '2025-06-01'),
(17, 6, 10, 'Project Manager', '2026-05-01'),
(18, 6,  9, 'Cost Analyst',    '2026-05-01');

-- two weeks: Monday 2026-09-21 and Monday 2026-09-28
INSERT INTO timesheets (timesheet_id, emp_id, week_start_date, status, approved_by) VALUES
( 1,  2, '2026-09-21', 'Approved',  1),
( 2,  3, '2026-09-21', 'Approved',  2),
( 3,  4, '2026-09-21', 'Approved',  2),
( 4,  5, '2026-09-21', 'Approved',  3),
( 5,  6, '2026-09-21', 'Approved',  2),
( 6,  7, '2026-09-21', 'Submitted', NULL),
( 7, 10, '2026-09-21', 'Approved',  1),
( 8, 11, '2026-09-21', 'Draft',     NULL),
( 9,  2, '2026-09-28', 'Approved',  1),
(10,  3, '2026-09-28', 'Submitted', NULL),
(11,  4, '2026-09-28', 'Approved',  2),
(12,  5, '2026-09-28', 'Rejected',  3),
(13,  6, '2026-09-28', 'Approved',  2),
(14, 13, '2026-09-28', 'Submitted', NULL);

INSERT INTO timesheet_entries (entry_id, timesheet_id, task_id, work_date, hours_worked, is_billable, description) VALUES
-- Week 2026-09-21
( 1,  1,  2, '2026-09-21', 3.00, 1, 'Sprint planning - API'),
( 2,  1,  5, '2026-09-22', 4.00, 1, 'Client call - tracking'),
( 3,  1,  8, '2026-09-23', 2.50, 1, 'Review patient module'),
( 4,  1,  2, '2026-09-24', 5.00, 1, 'API design review'),
( 5,  2,  2, '2026-09-21', 6.00, 1, 'Auth endpoints'),
( 6,  2,  5, '2026-09-22', 7.00, 1, 'GPS tracking logic'),
( 7,  2,  5, '2026-09-23', 6.50, 1, 'Map integration'),
( 8,  2,  3, '2026-09-24', 8.00, 1, 'Payment gateway'),
( 9,  3,  3, '2026-09-21', 8.00, 1, 'Payment SDK'),
(10,  3,  8, '2026-09-22', 7.50, 1, 'Patient registration'),
(11,  3,  2, '2026-09-23', 6.00, 1, 'Order API'),
(12,  3, 15, '2026-09-24', 2.00, 0, 'Warranty bug fix'),
(13,  4,  5, '2026-09-21', 8.00, 1, 'Tracking module'),
(14,  4,  8, '2026-09-22', 8.00, 1, 'Patient module'),
(15,  4,  8, '2026-09-23', 7.00, 1, 'Patient module'),
(16,  5,  9, '2026-09-21', 4.00, 1, 'Test plan update'),
(17,  5, 10, '2026-09-22', 7.00, 1, 'Selenium scripts'),
(18,  5, 10, '2026-09-23', 8.00, 1, 'Regression suite'),
(19,  6, 10, '2026-09-21', 8.00, 1, 'Automation scripts'),
(20,  6, 10, '2026-09-22', 6.00, 1, 'Automation scripts'),
(21,  7, 13, '2026-09-21', 5.00, 1, 'Analytics setup'),
(22,  7, 13, '2026-09-22', 6.00, 1, 'Dashboard data'),
(23,  8, 15, '2026-09-21', 4.00, 0, 'Learning + bug fixes'),
(24,  8,  2, '2026-09-22', 3.00, 1, 'Simple API endpoints'),
-- Week 2026-09-28
(25,  9,  2, '2026-09-28', 4.00, 1, 'Sprint planning'),
(26,  9,  8, '2026-09-29', 3.00, 1, 'Patient module review'),
(27,  9,  5, '2026-09-30', 5.00, 1, 'Client demo prep'),
(28, 10,  5, '2026-09-28', 8.00, 1, 'Tracking module'),
(29, 10,  2, '2026-09-29', 6.00, 1, 'Backend API'),
(30, 10, 15, '2026-09-30', 1.50, 0, 'Warranty bug fix'),
(31, 11,  8, '2026-09-28', 8.00, 1, 'Patient module'),
(32, 11,  3, '2026-09-29', 7.00, 1, 'Payment integration'),
(33, 12,  8, '2026-09-28', 8.00, 1, 'Patient module'),
(34, 12,  5, '2026-09-29', 6.00, 1, 'Tracking module'),
(35, 13, 10, '2026-09-28', 8.00, 1, 'Automation scripts'),
(36, 13,  9, '2026-09-29', 2.00, 1, 'Test plan'),
(37, 14,  5, '2026-09-28', 7.00, 1, 'Tracking module'),
(38, 14,  5, '2026-09-29', 8.00, 1, 'Tracking module'),
(39, 12,  3, '2026-09-30', 2.00, 0, 'Helped with payment bug');   -- Rohan is NOT assigned to project 1

INSERT INTO leave_types (leave_type_id, leave_name, annual_quota) VALUES
(1, 'Casual Leave', 12),
(2, 'Sick Leave',   10),
(3, 'Earned Leave', 15),
(4, 'Comp Off',      5);                            -- nobody has used this

INSERT INTO leave_requests (leave_id, emp_id, leave_type_id, from_date, to_date, days_taken, status) VALUES
(1,  3, 1, '2026-09-10', '2026-09-11', 2.0, 'Approved'),
(2,  4, 2, '2026-09-16', '2026-09-16', 1.0, 'Approved'),
(3,  6, 3, '2026-10-12', '2026-10-16', 5.0, 'Pending'),
(4,  6, 1, '2026-09-23', '2026-09-23', 1.0, 'Approved'),   -- overlaps Neha's timesheet entry on 23-Sep
(5,  8, 1, '2026-09-18', '2026-09-18', 1.0, 'Approved'),
(6,  5, 2, '2026-09-30', '2026-10-01', 2.0, 'Approved'),   -- overlaps Rohan's entries on 30-Sep
(7, 10, 3, '2026-10-05', '2026-10-09', 5.0, 'Approved'),
(8,  7, 2, '2026-09-25', '2026-09-25', 1.0, 'Approved');


/* =====================================================================
   PART C : JOIN QUERIES  (easy -> complex)
   ===================================================================== */

/* ########################  LEVEL 1 : INNER JOIN (2 tables)  ######################## */

-- 1.1  Employee with their department name.
--      Teaching point: INNER JOIN keeps only rows that match on BOTH sides.
--      Expected: 12 rows (Sanjay has no department, so he disappears).
SELECT e.emp_id, e.first_name, e.last_name, d.dept_name
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id;

-- 1.2  Projects with their client.  Expected: 6 rows (Internal HR Portal has no client).
SELECT p.project_id, p.project_name, c.client_name, c.country
FROM projects p
INNER JOIN clients c ON p.client_id = c.client_id;

-- 1.3  Tasks with their project name.  Expected: 15 rows.
SELECT t.task_id, t.task_name, p.project_name, t.estimated_hours
FROM tasks t
INNER JOIN projects p ON t.project_id = p.project_id
ORDER BY p.project_name, t.task_name;


/* ########################  LEVEL 2 : LEFT / RIGHT JOIN & "find the missing"  ######################## */

-- 2.1  All employees, even those without a department.
--      Teaching point: LEFT JOIN keeps EVERY row of the left table; unmatched right side = NULL.
--      Expected: 13 rows, Sanjay shows dept_name = NULL.
SELECT e.emp_id, e.first_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id;

-- 2.2  Departments that have NO employees  (anti-join: LEFT JOIN + IS NULL).
--      Expected: Legal.
SELECT d.dept_id, d.dept_name
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
WHERE e.emp_id IS NULL;

-- 2.3  Same data as 2.1 written as a RIGHT JOIN  (all departments, even Legal).
--      Teaching point: A RIGHT JOIN B  ==  B LEFT JOIN A.
--      Expected: 13 rows (12 employees + Legal with NULL employee).
SELECT d.dept_name, e.first_name, e.last_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id
ORDER BY d.dept_name;

-- 2.4  Clients who have no projects.  Expected: Orbit Telecom.
SELECT c.client_id, c.client_name
FROM clients c
LEFT JOIN projects p ON p.client_id = c.client_id
WHERE p.project_id IS NULL;

-- 2.5  Projects that have no tasks yet.  Expected: Internal HR Portal.
SELECT p.project_id, p.project_name
FROM projects p
LEFT JOIN tasks t ON t.project_id = p.project_id
WHERE t.task_id IS NULL;

-- 2.6  Tasks on which nobody has logged time.  Expected: 7 rows.
SELECT t.task_id, t.task_name, t.status
FROM tasks t
LEFT JOIN timesheet_entries te ON te.task_id = t.task_id
WHERE te.entry_id IS NULL;


/* ########################  LEVEL 3 : FULL OUTER JOIN (emulated) & CROSS JOIN  ######################## */

-- 3.1  FULL OUTER JOIN employees <-> departments.
--      MySQL has no FULL JOIN, so:  LEFT JOIN  UNION  RIGHT JOIN.
--      Expected: Sanjay (no dept) AND Legal (no employee) both appear.
SELECT e.first_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
UNION
SELECT e.first_name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id;

-- 3.2  CROSS JOIN: every Active Engineering employee x every leave type (a "grid").
--      Teaching point: no ON clause; rows = left rows x right rows.
SELECT e.first_name, lt.leave_name, lt.annual_quota
FROM employees e
CROSS JOIN leave_types lt
WHERE e.dept_id = 1 AND e.status = 'Active'
ORDER BY e.first_name, lt.leave_name;


/* ########################  LEVEL 4 : SELF JOIN  ######################## */

-- 4.1  Employee and their manager.   (same table, two aliases: e and m)
--      Expected: 13 rows, CEO Rajesh has manager = NULL.
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       CONCAT(m.first_name, ' ', m.last_name) AS manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.emp_id
ORDER BY manager, employee;

-- 4.2  Three-level hierarchy: employee -> manager -> manager's manager.
SELECT e.first_name  AS employee,
       m.first_name  AS manager,
       gm.first_name AS grand_manager
FROM employees e
LEFT JOIN employees m  ON e.manager_id = m.emp_id
LEFT JOIN employees gm ON m.manager_id = gm.emp_id;

-- 4.3  Number of direct reports per manager (self join + GROUP BY).
SELECT m.emp_id,
       CONCAT(m.first_name, ' ', m.last_name) AS manager,
       COUNT(e.emp_id) AS direct_reports
FROM employees m
INNER JOIN employees e ON e.manager_id = m.emp_id
GROUP BY m.emp_id, m.first_name, m.last_name
ORDER BY direct_reports DESC;

-- 4.4  Colleague pairs in the same department.
--      Teaching point: e1.emp_id < e2.emp_id removes (A,A) and the mirror pair (B,A).
SELECT e1.first_name AS employee_1, e2.first_name AS employee_2, e1.dept_id
FROM employees e1
INNER JOIN employees e2
        ON e1.dept_id = e2.dept_id
       AND e1.emp_id < e2.emp_id
ORDER BY e1.dept_id, e1.emp_id;


/* ########################  LEVEL 5 : MULTI-TABLE JOINS (3 to 6 tables)  ######################## */

-- 5.1  Employee profile: employee + designation + department + manager (4 tables).
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       ds.title                               AS designation,
       COALESCE(d.dept_name, 'Not assigned')  AS department,
       CONCAT(m.first_name, ' ', m.last_name) AS manager
FROM employees e
INNER JOIN designations ds ON ds.designation_id = e.designation_id
LEFT  JOIN departments  d  ON d.dept_id         = e.dept_id
LEFT  JOIN employees    m  ON m.emp_id           = e.manager_id
ORDER BY d.dept_name, ds.grade_level DESC;

-- 5.2  Who works on which project, for which client (many-to-many bridge, 4 tables).
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       pa.role_on_project,
       p.project_name,
       c.client_name
FROM project_assignments pa
INNER JOIN employees e ON e.emp_id    = pa.emp_id
INNER JOIN projects  p ON p.project_id = pa.project_id
INNER JOIN clients   c ON c.client_id  = p.client_id
ORDER BY p.project_name, pa.role_on_project;

-- 5.3  Project team with designation and department (5 tables).
SELECT p.project_name,
       CONCAT(e.first_name, ' ', e.last_name) AS member,
       pa.role_on_project,
       ds.title     AS designation,
       d.dept_name  AS home_department
FROM projects p
INNER JOIN project_assignments pa ON pa.project_id    = p.project_id
INNER JOIN employees           e  ON e.emp_id         = pa.emp_id
INNER JOIN designations        ds ON ds.designation_id = e.designation_id
LEFT  JOIN departments         d  ON d.dept_id        = e.dept_id
ORDER BY p.project_name, e.first_name;

-- 5.4  Full timesheet detail: entry -> timesheet -> employee -> task -> project -> client (6 tables).
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       c.client_name,
       p.project_name,
       t.task_name,
       te.work_date,
       te.hours_worked,
       ts.status AS timesheet_status
FROM timesheet_entries te
INNER JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
INNER JOIN employees  e  ON e.emp_id        = ts.emp_id
INNER JOIN tasks      t  ON t.task_id       = te.task_id
INNER JOIN projects   p  ON p.project_id    = t.project_id
INNER JOIN clients    c  ON c.client_id     = p.client_id
ORDER BY te.work_date, employee;


/* ########################  LEVEL 6 : MULTIPLE-COLUMN & NON-EQUI JOIN CONDITIONS  ######################## */

-- 6.1  Role of the employee ON THE PROJECT where they logged time.
--      Teaching point: the join to project_assignments needs TWO columns (project_id AND emp_id).
--      Expected: Rohan's entry on 'Payment Integration' has role = NULL (not assigned).
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       p.project_name,
       pa.role_on_project,
       t.task_name,
       te.work_date,
       te.hours_worked
FROM timesheet_entries te
INNER JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
INNER JOIN employees  e  ON e.emp_id        = ts.emp_id
INNER JOIN tasks      t  ON t.task_id       = te.task_id
INNER JOIN projects   p  ON p.project_id    = t.project_id
LEFT  JOIN project_assignments pa
        ON pa.project_id = p.project_id
       AND pa.emp_id     = e.emp_id
ORDER BY employee, te.work_date;

-- 6.2  Week-over-week timesheet status (self join on TWO columns: employee AND week).
--      Expected: employees with timesheets in both weeks show both statuses.
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       cur.week_start_date  AS this_week,
       cur.status           AS this_week_status,
       prev.status          AS previous_week_status
FROM timesheets cur
INNER JOIN employees e ON e.emp_id = cur.emp_id
LEFT  JOIN timesheets prev
        ON prev.emp_id          = cur.emp_id
       AND prev.week_start_date = DATE_SUB(cur.week_start_date, INTERVAL 7 DAY)
WHERE cur.week_start_date = '2026-09-28';

-- 6.3  NON-EQUI JOIN: time logged on a day the employee was on approved leave.
--      Teaching point: ON can use BETWEEN / <, > instead of "=".
--      Expected: Neha (23-Sep) and Rohan (30-Sep).
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       te.work_date,
       te.hours_worked,
       lt.leave_name,
       lr.from_date, lr.to_date
FROM timesheet_entries te
INNER JOIN timesheets    ts ON ts.timesheet_id = te.timesheet_id
INNER JOIN employees     e  ON e.emp_id        = ts.emp_id
INNER JOIN leave_requests lr
        ON lr.emp_id = ts.emp_id
       AND lr.status = 'Approved'
       AND te.work_date BETWEEN lr.from_date AND lr.to_date
INNER JOIN leave_types   lt ON lt.leave_type_id = lr.leave_type_id;

-- 6.4  Leave history with employee, department and leave type (multi-table, filtered in ON).
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       d.dept_name,
       lt.leave_name,
       lr.from_date, lr.to_date, lr.days_taken, lr.status
FROM leave_requests lr
INNER JOIN employees   e  ON e.emp_id         = lr.emp_id
LEFT  JOIN departments d  ON d.dept_id        = e.dept_id
INNER JOIN leave_types lt ON lt.leave_type_id = lr.leave_type_id
ORDER BY lr.from_date;


/* ########################  LEVEL 7 : JOINS + AGGREGATION (GROUP BY / HAVING)  ######################## */

-- 7.1  Total hours per employee, INCLUDING employees who logged nothing (0 hours).
--      Teaching point: COALESCE turns the NULL SUM into 0; use LEFT JOINs all the way down.
SELECT e.emp_id,
       CONCAT(e.first_name, ' ', e.last_name) AS employee,
       COALESCE(SUM(te.hours_worked), 0)      AS total_hours
FROM employees e
LEFT JOIN timesheets        ts ON ts.emp_id       = e.emp_id
LEFT JOIN timesheet_entries te ON te.timesheet_id = ts.timesheet_id
GROUP BY e.emp_id, e.first_name, e.last_name
ORDER BY total_hours DESC;

-- 7.2  Billable vs non-billable hours per project.
SELECT p.project_name,
       SUM(CASE WHEN te.is_billable = 1 THEN te.hours_worked ELSE 0 END) AS billable_hours,
       SUM(CASE WHEN te.is_billable = 0 THEN te.hours_worked ELSE 0 END) AS non_billable_hours,
       SUM(te.hours_worked)                                              AS total_hours
FROM timesheet_entries te
INNER JOIN tasks    t ON t.task_id    = te.task_id
INNER JOIN projects p ON p.project_id = t.project_id
GROUP BY p.project_id, p.project_name
ORDER BY total_hours DESC;

-- 7.3  Labour cost per project vs budget  (hours x employee hourly rate).
SELECT p.project_name,
       p.budget,
       SUM(te.hours_worked * e.hourly_rate)                         AS labour_cost,
       ROUND(SUM(te.hours_worked * e.hourly_rate) / p.budget * 100, 2) AS budget_used_pct
FROM projects p
INNER JOIN tasks             t  ON t.project_id    = p.project_id
INNER JOIN timesheet_entries te ON te.task_id      = t.task_id
INNER JOIN timesheets        ts ON ts.timesheet_id = te.timesheet_id
INNER JOIN employees         e  ON e.emp_id        = ts.emp_id
GROUP BY p.project_id, p.project_name, p.budget
ORDER BY labour_cost DESC;

-- 7.4  Department-wise hours and cost, including departments with zero activity (Legal, HR...).
SELECT d.dept_name,
       COUNT(DISTINCT e.emp_id)                     AS employees,
       COALESCE(SUM(te.hours_worked), 0)            AS total_hours,
       COALESCE(SUM(te.hours_worked * e.hourly_rate), 0) AS total_cost
FROM departments d
LEFT JOIN employees         e  ON e.dept_id       = d.dept_id
LEFT JOIN timesheets        ts ON ts.emp_id       = e.emp_id
LEFT JOIN timesheet_entries te ON te.timesheet_id = ts.timesheet_id
GROUP BY d.dept_id, d.dept_name
ORDER BY total_hours DESC;

-- 7.5  Client-wise total hours (5-table chain, LEFT JOIN so Orbit Telecom shows 0).
SELECT c.client_name,
       COUNT(DISTINCT p.project_id)      AS projects,
       COALESCE(SUM(te.hours_worked), 0) AS total_hours
FROM clients c
LEFT JOIN projects          p  ON p.client_id  = c.client_id
LEFT JOIN tasks             t  ON t.project_id = p.project_id
LEFT JOIN timesheet_entries te ON te.task_id   = t.task_id
GROUP BY c.client_id, c.client_name
ORDER BY total_hours DESC;

-- 7.6  Timesheet status count per department (conditional aggregation).
SELECT d.dept_name,
       SUM(ts.status = 'Draft')     AS draft,
       SUM(ts.status = 'Submitted') AS submitted,
       SUM(ts.status = 'Approved')  AS approved,
       SUM(ts.status = 'Rejected')  AS rejected
FROM departments d
INNER JOIN employees  e  ON e.dept_id = d.dept_id
INNER JOIN timesheets ts ON ts.emp_id = e.emp_id
GROUP BY d.dept_id, d.dept_name;

-- 7.7  HAVING on a joined aggregate: employees who logged more than 25 hours in total.
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       SUM(te.hours_worked)                   AS total_hours
FROM employees e
INNER JOIN timesheets        ts ON ts.emp_id       = e.emp_id
INNER JOIN timesheet_entries te ON te.timesheet_id = ts.timesheet_id
GROUP BY e.emp_id, e.first_name, e.last_name
HAVING SUM(te.hours_worked) > 25
ORDER BY total_hours DESC;

-- 7.8  Leave balance for every active employee x every leave type
--      (CROSS JOIN builds the grid, LEFT JOIN with 3 conditions adds usage).
--      Teaching point: the filter lr.status='Approved' must stay in ON, not WHERE,
--      otherwise employees with no leave disappear.
SELECT CONCAT(e.first_name, ' ', e.last_name)      AS employee,
       lt.leave_name,
       lt.annual_quota,
       COALESCE(SUM(lr.days_taken), 0)             AS used,
       lt.annual_quota - COALESCE(SUM(lr.days_taken), 0) AS balance
FROM employees e
CROSS JOIN leave_types lt
LEFT JOIN leave_requests lr
       ON lr.emp_id        = e.emp_id
      AND lr.leave_type_id = lt.leave_type_id
      AND lr.status        = 'Approved'
WHERE e.status = 'Active'
GROUP BY e.emp_id, e.first_name, e.last_name, lt.leave_type_id, lt.leave_name, lt.annual_quota
ORDER BY employee, lt.leave_name;


/* ########################  LEVEL 8 : COMPLEX  (subqueries, CTEs, window functions)  ######################## */

-- 8.1  Employees who have NEVER submitted a timesheet (NOT EXISTS) with department,
--      designation and manager.   Expected: Rajesh, Anjali, Vikram, Meera.
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       ds.title                                AS designation,
       d.dept_name,
       CONCAT(m.first_name, ' ', m.last_name)  AS manager
FROM employees e
INNER JOIN designations ds ON ds.designation_id = e.designation_id
LEFT  JOIN departments  d  ON d.dept_id         = e.dept_id
LEFT  JOIN employees    m  ON m.emp_id          = e.manager_id
WHERE NOT EXISTS (SELECT 1 FROM timesheets ts WHERE ts.emp_id = e.emp_id);

-- 8.2  Timesheet approval audit: employee, approver (same table twice), total hours.
--      Pending timesheets show approver = NULL.
SELECT CONCAT(e.first_name, ' ', e.last_name)  AS employee,
       ts.week_start_date,
       ts.status,
       CONCAT(a.first_name, ' ', a.last_name)  AS approved_by,
       h.total_hours
FROM timesheets ts
INNER JOIN employees e ON e.emp_id = ts.emp_id
LEFT  JOIN employees a ON a.emp_id = ts.approved_by
LEFT  JOIN (SELECT timesheet_id, SUM(hours_worked) AS total_hours
            FROM timesheet_entries
            GROUP BY timesheet_id) h ON h.timesheet_id = ts.timesheet_id
ORDER BY ts.week_start_date, employee;

-- 8.3  Weekly hours per employee with the previous week side by side (CTE + self join on 2 columns).
WITH weekly AS (
    SELECT ts.emp_id, ts.week_start_date, SUM(te.hours_worked) AS hrs
    FROM timesheets ts
    INNER JOIN timesheet_entries te ON te.timesheet_id = ts.timesheet_id
    GROUP BY ts.emp_id, ts.week_start_date
)
SELECT CONCAT(e.first_name, ' ', e.last_name)  AS employee,
       cur.week_start_date,
       cur.hrs                                 AS this_week_hours,
       prev.hrs                                AS previous_week_hours,
       cur.hrs - prev.hrs                      AS change_in_hours,
       ROUND(cur.hrs / 40 * 100, 1)            AS utilisation_pct_of_40h
FROM weekly cur
INNER JOIN employees e ON e.emp_id = cur.emp_id
LEFT  JOIN weekly prev
        ON prev.emp_id          = cur.emp_id
       AND prev.week_start_date = DATE_SUB(cur.week_start_date, INTERVAL 7 DAY)
WHERE cur.week_start_date = '2026-09-28'
ORDER BY cur.hrs DESC;

-- 8.4  Rank employees inside their department by hours worked (CTE + window function).
WITH emp_hours AS (
    SELECT e.emp_id, e.first_name, e.last_name, e.dept_id,
           COALESCE(SUM(te.hours_worked), 0) AS total_hours
    FROM employees e
    LEFT JOIN timesheets        ts ON ts.emp_id       = e.emp_id
    LEFT JOIN timesheet_entries te ON te.timesheet_id = ts.timesheet_id
    GROUP BY e.emp_id, e.first_name, e.last_name, e.dept_id
)
SELECT d.dept_name,
       CONCAT(eh.first_name, ' ', eh.last_name) AS employee,
       eh.total_hours,
       RANK() OVER (PARTITION BY d.dept_id ORDER BY eh.total_hours DESC) AS dept_rank
FROM emp_hours eh
INNER JOIN departments d ON d.dept_id = eh.dept_id
ORDER BY d.dept_name, dept_rank;

-- 8.5  Task progress: logged hours vs estimate (join + aggregate + calculation).
SELECT p.project_name,
       t.task_name,
       t.estimated_hours,
       COALESCE(SUM(te.hours_worked), 0)                                   AS actual_hours,
       ROUND(COALESCE(SUM(te.hours_worked), 0) / t.estimated_hours * 100, 1) AS pct_of_estimate_used,
       t.status
FROM tasks t
INNER JOIN projects p ON p.project_id = t.project_id
LEFT  JOIN timesheet_entries te ON te.task_id = t.task_id
GROUP BY t.task_id, p.project_name, t.task_name, t.estimated_hours, t.status
ORDER BY p.project_name, pct_of_estimate_used DESC;

-- 8.6  Data-quality check: time logged on a project the employee is NOT assigned to
--      (LEFT JOIN on two columns + IS NULL).   Expected: Rohan Das -> Retail Mobile App.
SELECT CONCAT(e.first_name, ' ', e.last_name) AS employee,
       p.project_name,
       t.task_name,
       te.work_date,
       te.hours_worked
FROM timesheet_entries te
INNER JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
INNER JOIN employees  e  ON e.emp_id        = ts.emp_id
INNER JOIN tasks      t  ON t.task_id       = te.task_id
INNER JOIN projects   p  ON p.project_id    = t.project_id
LEFT  JOIN project_assignments pa
        ON pa.project_id = p.project_id
       AND pa.emp_id     = e.emp_id
WHERE pa.assignment_id IS NULL;

-- 8.7  Employees working on MORE THAN ONE project (join + GROUP BY + HAVING + GROUP_CONCAT).
SELECT CONCAT(e.first_name, ' ', e.last_name)       AS employee,
       COUNT(DISTINCT pa.project_id)                AS project_count,
       GROUP_CONCAT(p.project_name ORDER BY p.project_name SEPARATOR ', ') AS projects
FROM employees e
INNER JOIN project_assignments pa ON pa.emp_id     = e.emp_id
INNER JOIN projects            p  ON p.project_id  = pa.project_id
GROUP BY e.emp_id, e.first_name, e.last_name
HAVING COUNT(DISTINCT pa.project_id) > 1
ORDER BY project_count DESC;

-- 8.8  MASTER PROJECT DASHBOARD  (10-table query).
--      Teaching point: aggregate in derived tables first, THEN join, to avoid "fan-out"
--      (counting the same row several times when joining one-to-many tables together).
SELECT p.project_id,
       p.project_name,
       COALESCE(c.client_name, 'Internal')               AS client,
       d.dept_name                                       AS owning_department,
       CONCAT(pme.first_name, ' ', pme.last_name)        AS project_manager,
       COALESCE(team.team_size, 0)                       AS team_size,
       COALESCE(hrs.total_hours, 0)                      AS total_hours,
       COALESCE(hrs.total_cost, 0)                       AS labour_cost,
       p.budget,
       ROUND(COALESCE(hrs.total_cost, 0) / p.budget * 100, 2) AS budget_used_pct
FROM projects p
LEFT  JOIN clients  c   ON c.client_id = p.client_id
INNER JOIN departments d ON d.dept_id  = p.dept_id
LEFT  JOIN project_assignments pm
        ON pm.project_id      = p.project_id
       AND pm.role_on_project = 'Project Manager'
LEFT  JOIN employees pme ON pme.emp_id = pm.emp_id
LEFT  JOIN (SELECT project_id, COUNT(*) AS team_size
            FROM project_assignments
            GROUP BY project_id) team ON team.project_id = p.project_id
LEFT  JOIN (SELECT t.project_id,
                   SUM(te.hours_worked)                  AS total_hours,
                   SUM(te.hours_worked * e.hourly_rate)  AS total_cost
            FROM timesheet_entries te
            INNER JOIN tasks      t  ON t.task_id       = te.task_id
            INNER JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
            INNER JOIN employees  e  ON e.emp_id        = ts.emp_id
            GROUP BY t.project_id) hrs ON hrs.project_id = p.project_id
ORDER BY p.project_id;

/* ===================== END OF SCRIPT ===================== */
