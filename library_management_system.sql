CREATE DATABASE IF NOT EXISTS library_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE library_db;

SET FOREIGN_KEY_CHECKS = 0;

DROP VIEW IF EXISTS overdue_loans;
DROP VIEW IF EXISTS book_inventory;
DROP PROCEDURE IF EXISTS borrow_book;
DROP PROCEDURE IF EXISTS return_book;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS books;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS authors;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE authors (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    country VARCHAR(100)
);

CREATE TABLE members (
    member_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(30),
    joined_at DATE NOT NULL DEFAULT (CURRENT_DATE)
);

CREATE TABLE books (
    book_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    author_id INT NOT NULL,
    isbn VARCHAR(20) UNIQUE,
    publication_year SMALLINT,
    category VARCHAR(100),
    copies_total INT NOT NULL DEFAULT 1,
    copies_available INT NOT NULL DEFAULT 1,
    CONSTRAINT chk_book_copies
        CHECK (copies_total >= 0 AND copies_available >= 0
               AND copies_available <= copies_total),
    CONSTRAINT fk_books_author
        FOREIGN KEY (author_id) REFERENCES authors(author_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE TABLE loans (
    loan_id INT AUTO_INCREMENT PRIMARY KEY,
    book_id INT NOT NULL,
    member_id INT NOT NULL,
    loan_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    due_date DATE NOT NULL,
    return_date DATE NULL,
    CONSTRAINT fk_loans_book
        FOREIGN KEY (book_id) REFERENCES books(book_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_loans_member
        FOREIGN KEY (member_id) REFERENCES members(member_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

ALTER TABLE books
    ADD COLUMN shelf_location VARCHAR(50) NULL;

INSERT INTO authors (full_name, country) VALUES
('نجيب محفوظ', 'مصر'),
('غسان كنفاني', 'فلسطين'),
('جبران خليل جبران', 'لبنان'),
('أحمد خالد توفيق', 'مصر');

INSERT INTO members (full_name, email, phone) VALUES
('سارة أحمد', 'sara@example.com', '0501234567'),
('عمر خالد', 'omar@example.com', '0507654321'),
('ليلى حسن', 'layla@example.com', '0551122334');

INSERT INTO books
    (title, author_id, isbn, publication_year, category,
     copies_total, copies_available, shelf_location)
VALUES
('بين القصرين', 1, '9789770000001', 1956, 'رواية', 3, 3, 'A-01'),
('رجال في الشمس', 2, '9789950000002', 1963, 'رواية', 2, 2, 'A-02'),
('النبي', 3, '9789950000003', 1923, 'أدب', 2, 2, 'B-01'),
('يوتوبيا', 4, '9789770000004', 2008, 'خيال علمي', 4, 4, 'C-01');

INSERT INTO loans (book_id, member_id, loan_date, due_date, return_date)
VALUES
(1, 1, DATE_SUB(CURRENT_DATE, INTERVAL 20 DAY),
 DATE_SUB(CURRENT_DATE, INTERVAL 6 DAY), NULL),
(2, 2, DATE_SUB(CURRENT_DATE, INTERVAL 5 DAY),
 DATE_ADD(CURRENT_DATE, INTERVAL 9 DAY), NULL),
(3, 3, DATE_SUB(CURRENT_DATE, INTERVAL 30 DAY),
 DATE_SUB(CURRENT_DATE, INTERVAL 16 DAY),
 DATE_SUB(CURRENT_DATE, INTERVAL 10 DAY));

-- عرض الكتب مع أسماء مؤلفيها
SELECT
    b.book_id,
    b.title,
    a.full_name AS author,
    b.category,
    b.copies_available,
    b.shelf_location
FROM books AS b
INNER JOIN authors AS a ON a.author_id = b.author_id
ORDER BY b.title;

-- الكتب المتاحة للاستعارة
SELECT title, category, copies_available
FROM books
WHERE copies_available > 0
ORDER BY title;

-- عدد الكتب لكل تصنيف
SELECT category, COUNT(*) AS book_titles,
       SUM(copies_total) AS total_copies
FROM books
GROUP BY category
ORDER BY total_copies DESC;

-- عدد الاستعارات لكل عضو
SELECT
    m.full_name,
    COUNT(l.loan_id) AS loan_count
FROM members AS m
LEFT JOIN loans AS l ON l.member_id = m.member_id
GROUP BY m.member_id, m.full_name
ORDER BY loan_count DESC;

-- عرض الاستعارات المتأخرة
SELECT
    m.full_name AS member,
    b.title AS book,
    l.loan_date,
    l.due_date
FROM loans AS l
INNER JOIN members AS m ON m.member_id = l.member_id
INNER JOIN books AS b ON b.book_id = l.book_id
WHERE l.return_date IS NULL
  AND l.due_date < CURRENT_DATE
ORDER BY l.due_date;

DELIMITER $$

CREATE PROCEDURE borrow_book(
    IN p_book_id INT,
    IN p_member_id INT,
    IN p_loan_days INT
)
BEGIN
    DECLARE v_available INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_loan_days < 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'مدة الاستعارة يجب أن تكون يومًا واحدًا على الأقل';
    END IF;

    START TRANSACTION;

    SELECT copies_available
    INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF v_available IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'الكتاب غير موجود';
    ELSEIF v_available < 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'لا توجد نسخ متاحة من الكتاب';
    ELSEIF NOT EXISTS (
        SELECT 1 FROM members WHERE member_id = p_member_id
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'العضو غير موجود';
    ELSE
        INSERT INTO loans (book_id, member_id, loan_date, due_date)
        VALUES (
            p_book_id,
            p_member_id,
            CURRENT_DATE,
            DATE_ADD(CURRENT_DATE, INTERVAL p_loan_days DAY)
        );

        UPDATE books
        SET copies_available = copies_available - 1
        WHERE book_id = p_book_id;

        COMMIT;
    END IF;
END$$

CREATE PROCEDURE return_book(IN p_loan_id INT)
BEGIN
    DECLARE v_book_id INT DEFAULT NULL;
    DECLARE v_return_date DATE DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT book_id, return_date
    INTO v_book_id, v_return_date
    FROM loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF v_book_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'سجل الاستعارة غير موجود';
    ELSEIF v_return_date IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'تم إرجاع هذا الكتاب مسبقًا';
    ELSE
        UPDATE loans
        SET return_date = CURRENT_DATE
        WHERE loan_id = p_loan_id;

        UPDATE books
        SET copies_available = copies_available + 1
        WHERE book_id = v_book_id;

        COMMIT;
    END IF;
END$$

DELIMITER ;

CREATE VIEW book_inventory AS
SELECT
    b.book_id,
    b.title,
    a.full_name AS author,
    b.category,
    b.copies_total,
    b.copies_available,
    b.shelf_location
FROM books AS b
INNER JOIN authors AS a ON a.author_id = b.author_id;

CREATE VIEW overdue_loans AS
SELECT
    l.loan_id,
    m.full_name AS member,
    b.title AS book,
    l.loan_date,
    l.due_date,
    DATEDIFF(CURRENT_DATE, l.due_date) AS days_overdue
FROM loans AS l
INNER JOIN members AS m ON m.member_id = l.member_id
INNER JOIN books AS b ON b.book_id = l.book_id
WHERE l.return_date IS NULL
  AND l.due_date < CURRENT_DATE;

-- أمثلة تشغيل الإجراءات:
-- استعارة الكتاب رقم 4 للعضو رقم 1 لمدة 14 يومًا
-- CALL borrow_book(4, 1, 14);

-- إرجاع الاستعارة رقم 2
-- CALL return_book(2);

-- عرض المخزون والاستعارات المتأخرة
-- SELECT * FROM book_inventory;
-- SELECT * FROM overdue_loans;
