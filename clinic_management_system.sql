CREATE DATABASE IF NOT EXISTS clinic_management_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE clinic_management_db;

SET FOREIGN_KEY_CHECKS = 0;

DROP VIEW IF EXISTS upcoming_appointments;
DROP VIEW IF EXISTS doctor_directory;
DROP PROCEDURE IF EXISTS book_appointment;
DROP PROCEDURE IF EXISTS cancel_appointment;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS patients;
DROP TABLE IF EXISTS doctors;
DROP TABLE IF EXISTS departments;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE departments (
    department_id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    location VARCHAR(100)
);

CREATE TABLE doctors (
    doctor_id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(30),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_doctors_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE TABLE patients (
    patient_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    date_of_birth DATE,
    email VARCHAR(150) UNIQUE,
    phone VARCHAR(30) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointments (
    appointment_id INT AUTO_INCREMENT PRIMARY KEY,
    doctor_id INT NOT NULL,
    patient_id INT NOT NULL,
    appointment_start DATETIME NOT NULL,
    appointment_end DATETIME NOT NULL,
    status ENUM('scheduled', 'completed', 'cancelled') NOT NULL DEFAULT 'scheduled',
    reason VARCHAR(500),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_appointment_time
        CHECK (appointment_end > appointment_start),
    CONSTRAINT fk_appointments_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_appointments_patient
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

ALTER TABLE appointments
    ADD COLUMN notes VARCHAR(500) NULL;

INSERT INTO departments (department_name, location) VALUES
('Family Medicine', 'Building A'),
('Cardiology', 'Building B'),
('Dermatology', 'Building A');

INSERT INTO doctors (department_id, full_name, email, phone) VALUES
(1, 'Dr. Amal Hassan', 'amal.hassan@clinic.example', '0501112233'),
(2, 'Dr. Sami Khaled', 'sami.khaled@clinic.example', '0502223344'),
(3, 'Dr. Noor Saleh', 'noor.saleh@clinic.example', '0503334455');

INSERT INTO patients (full_name, date_of_birth, email, phone) VALUES
('Maya Ahmed', '1995-04-12', 'maya@example.com', '0551112233'),
('Omar Ali', '1988-09-25', 'omar@example.com', '0552223344'),
('Lina Saeed', '2001-01-08', 'lina@example.com', '0553334455');

INSERT INTO appointments (
    doctor_id,
    patient_id,
    appointment_start,
    appointment_end,
    status,
    reason
) VALUES
(
    1,
    1,
    DATE_ADD(CURRENT_DATE, INTERVAL 1 DAY) + INTERVAL 9 HOUR,
    DATE_ADD(CURRENT_DATE, INTERVAL 1 DAY) + INTERVAL 9 HOUR + INTERVAL 30 MINUTE,
    'scheduled',
    'Routine checkup'
),
(
    2,
    2,
    DATE_ADD(CURRENT_DATE, INTERVAL 2 DAY) + INTERVAL 11 HOUR,
    DATE_ADD(CURRENT_DATE, INTERVAL 2 DAY) + INTERVAL 11 HOUR + INTERVAL 30 MINUTE,
    'scheduled',
    'Heart consultation'
),
(
    3,
    3,
    DATE_SUB(CURRENT_DATE, INTERVAL 5 DAY) + INTERVAL 14 HOUR,
    DATE_SUB(CURRENT_DATE, INTERVAL 5 DAY) + INTERVAL 14 HOUR + INTERVAL 30 MINUTE,
    'completed',
    'Skin consultation'
);

SELECT
    a.appointment_id,
    p.full_name AS patient_name,
    d.full_name AS doctor_name,
    dep.department_name,
    a.appointment_start,
    a.appointment_end,
    a.status
FROM appointments AS a
INNER JOIN patients AS p ON p.patient_id = a.patient_id
INNER JOIN doctors AS d ON d.doctor_id = a.doctor_id
INNER JOIN departments AS dep ON dep.department_id = d.department_id
ORDER BY a.appointment_start;

SELECT
    dep.department_name,
    COUNT(d.doctor_id) AS doctor_count
FROM departments AS dep
LEFT JOIN doctors AS d
    ON d.department_id = dep.department_id
   AND d.is_active = TRUE
GROUP BY dep.department_id, dep.department_name
ORDER BY doctor_count DESC;

SELECT
    p.full_name,
    COUNT(a.appointment_id) AS appointment_count
FROM patients AS p
LEFT JOIN appointments AS a ON a.patient_id = p.patient_id
GROUP BY p.patient_id, p.full_name
ORDER BY appointment_count DESC;

SELECT
    d.full_name AS doctor_name,
    a.appointment_start,
    a.appointment_end,
    p.full_name AS patient_name
FROM appointments AS a
INNER JOIN doctors AS d ON d.doctor_id = a.doctor_id
INNER JOIN patients AS p ON p.patient_id = a.patient_id
WHERE a.status = 'scheduled'
  AND a.appointment_start >= CURRENT_TIMESTAMP
ORDER BY a.appointment_start;

DELIMITER $$

CREATE PROCEDURE book_appointment(
    IN p_doctor_id INT,
    IN p_patient_id INT,
    IN p_start DATETIME,
    IN p_end DATETIME,
    IN p_reason VARCHAR(500)
)
BEGIN
    DECLARE v_doctor_active BOOLEAN DEFAULT NULL;
    DECLARE v_conflicts INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_end <= p_start THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Appointment end must be after its start';
    END IF;

    START TRANSACTION;

    SELECT is_active
    INTO v_doctor_active
    FROM doctors
    WHERE doctor_id = p_doctor_id
    FOR UPDATE;

    IF v_doctor_active IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Doctor not found';
    ELSEIF v_doctor_active = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Doctor is not active';
    ELSEIF NOT EXISTS (
        SELECT 1
        FROM patients
        WHERE patient_id = p_patient_id
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient not found';
    END IF;

    SELECT COUNT(*)
    INTO v_conflicts
    FROM appointments
    WHERE doctor_id = p_doctor_id
      AND status = 'scheduled'
      AND p_start < appointment_end
      AND p_end > appointment_start;

    IF v_conflicts > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Doctor already has an appointment at that time';
    END IF;

    INSERT INTO appointments (
        doctor_id,
        patient_id,
        appointment_start,
        appointment_end,
        reason
    )
    VALUES (
        p_doctor_id,
        p_patient_id,
        p_start,
        p_end,
        p_reason
    );

    COMMIT;
END$$

CREATE PROCEDURE cancel_appointment(IN p_appointment_id INT)
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status
    INTO v_status
    FROM appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Appointment not found';
    ELSEIF v_status <> 'scheduled' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only scheduled appointments can be cancelled';
    ELSE
        UPDATE appointments
        SET status = 'cancelled'
        WHERE appointment_id = p_appointment_id;

        COMMIT;
    END IF;
END$$

DELIMITER ;

CREATE VIEW doctor_directory AS
SELECT
    d.doctor_id,
    d.full_name AS doctor_name,
    d.email,
    d.phone,
    dep.department_name,
    dep.location
FROM doctors AS d
INNER JOIN departments AS dep
    ON dep.department_id = d.department_id
WHERE d.is_active = TRUE;

CREATE VIEW upcoming_appointments AS
SELECT
    a.appointment_id,
    p.full_name AS patient_name,
    d.full_name AS doctor_name,
    dep.department_name,
    a.appointment_start,
    a.appointment_end,
    a.reason
FROM appointments AS a
INNER JOIN patients AS p ON p.patient_id = a.patient_id
INNER JOIN doctors AS d ON d.doctor_id = a.doctor_id
INNER JOIN departments AS dep ON dep.department_id = d.department_id
WHERE a.status = 'scheduled'
  AND a.appointment_start >= CURRENT_TIMESTAMP;

SELECT * FROM doctor_directory;
SELECT * FROM upcoming_appointments;
