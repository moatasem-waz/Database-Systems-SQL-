CREATE DATABASE IF NOT EXISTS company_db;
USE company_db;


CREATE TABLE departments (
    department_id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    location VARCHAR(100)
);

CREATE TABLE employees (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    hire_date DATE NOT NULL,
    salary DECIMAL(10, 2) NOT NULL,
    department_id INT,
    CONSTRAINT chk_employee_salary CHECK (salary >= 0),
    CONSTRAINT fk_employees_department
        FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE projects (
    project_id INT AUTO_INCREMENT PRIMARY KEY,
    project_name VARCHAR(120) NOT NULL,
    start_date DATE,
    end_date DATE,
    budget DECIMAL(12, 2) DEFAULT 0.00,
    CONSTRAINT chk_project_budget CHECK (budget >= 0)
);

CREATE TABLE employee_projects (
    employee_id INT NOT NULL,
    project_id INT NOT NULL,
    assigned_date DATE NOT NULL,
    hours_worked DECIMAL(8, 2) DEFAULT 0.00,
    PRIMARY KEY (employee_id, project_id),
    CONSTRAINT fk_employee_projects_employee
        FOREIGN KEY (employee_id)
        REFERENCES employees(employee_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_employee_projects_project
        FOREIGN KEY (project_id)
        REFERENCES projects(project_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);


INSERT INTO departments (department_name, location) VALUES
('تقنية المعلومات', 'الرياض'),
('الموارد البشرية', 'جدة'),
('المبيعات', 'الدمام');

INSERT INTO employees
(first_name, last_name, email, hire_date, salary, department_id)
VALUES
('أحمد', 'محمد', 'ahmed@example.com', '2022-03-15', 8500.00, 1),
('سارة', 'علي', 'sara@example.com', '2021-07-01', 9200.00, 1),
('خالد', 'حسن', 'khaled@example.com', '2023-01-10', 7000.00, 2),
('نورة', 'سعيد', 'noura@example.com', '2020-11-20', 7800.00, 3);

INSERT INTO projects (project_name, start_date, end_date, budget) VALUES
('تطوير الموقع', '2025-01-01', '2025-06-30', 50000.00),
('نظام الموارد البشرية', '2025-02-01', '2025-09-30', 75000.00);

INSERT INTO employee_projects
(employee_id, project_id, assigned_date, hours_worked)
VALUES
(1, 1, '2025-01-05', 40.00),
(2, 1, '2025-01-06', 32.00),
(2, 2, '2025-02-03', 20.00),
(3, 2, '2025-02-05', 35.00);


SELECT *
FROM employees;

SELECT first_name, last_name, email, salary
FROM employees
WHERE salary >= 8000
ORDER BY salary DESC;

SELECT
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name
FROM employees AS e
INNER JOIN departments AS d
    ON e.department_id = d.department_id;

SELECT
    e.first_name,
    e.last_name,
    p.project_name,
    ep.hours_worked
FROM employee_projects AS ep
INNER JOIN employees AS e
    ON ep.employee_id = e.employee_id
INNER JOIN projects AS p
    ON ep.project_id = p.project_id
ORDER BY p.project_name, e.last_name;

SELECT
    d.department_name,
    COUNT(e.employee_id) AS employee_count
FROM departments AS d
LEFT JOIN employees AS e
    ON d.department_id = e.department_id
GROUP BY d.department_id, d.department_name
ORDER BY employee_count DESC;

SELECT
    d.department_name,
    AVG(e.salary) AS average_salary
FROM departments AS d
INNER JOIN employees AS e
    ON d.department_id = e.department_id
GROUP BY d.department_id, d.department_name;

SELECT project_name, budget
FROM projects
WHERE budget > 50000
ORDER BY budget DESC;

SELECT
    p.project_name,
    COALESCE(SUM(ep.hours_worked), 0) AS total_hours
FROM projects AS p
LEFT JOIN employee_projects AS ep
    ON p.project_id = ep.project_id
GROUP BY p.project_id, p.project_name;


CREATE OR REPLACE VIEW employee_department_view AS
SELECT
    e.employee_id,
    e.first_name,
    e.last_name,
    e.email,
    e.hire_date,
    e.salary,
    d.department_name,
    d.location AS department_location
FROM employees AS e
LEFT JOIN departments AS d
    ON e.department_id = d.department_id;

CREATE OR REPLACE VIEW project_employee_summary AS
SELECT
    p.project_id,
    p.project_name,
    COUNT(ep.employee_id) AS assigned_employee_count,
    COALESCE(SUM(ep.hours_worked), 0) AS total_hours
FROM projects AS p
LEFT JOIN employee_projects AS ep
    ON p.project_id = ep.project_id
GROUP BY p.project_id, p.project_name;


DELIMITER //

CREATE PROCEDURE GetEmployeesByDepartment(
    IN department_name_input VARCHAR(100)
)
BEGIN
    SELECT
        e.employee_id,
        e.first_name,
        e.last_name,
        e.email,
        e.salary,
        d.department_name
    FROM employees AS e
    INNER JOIN departments AS d
        ON e.department_id = d.department_id
    WHERE d.department_name = department_name_input
    ORDER BY e.last_name, e.first_name;
END //

DELIMITER ;


SELECT * FROM employee_department_view;
SELECT * FROM project_employee_summary;
CALL GetEmployeesByDepartment('تقنية المعلومات');
