CREATE DATABASE IF NOT EXISTS online_store_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE online_store_db;

SET FOREIGN_KEY_CHECKS = 0;

DROP VIEW IF EXISTS product_inventory;
DROP VIEW IF EXISTS order_details;
DROP PROCEDURE IF EXISTS place_order;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS categories;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(500)
);

CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(30),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    category_id INT NOT NULL,
    product_name VARCHAR(150) NOT NULL,
    description VARCHAR(500),
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_product_price CHECK (price >= 0),
    CONSTRAINT chk_product_stock CHECK (stock_quantity >= 0),
    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES categories(category_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE TABLE orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    order_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'paid', 'shipped', 'cancelled') NOT NULL DEFAULT 'pending',
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE TABLE order_items (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    CONSTRAINT chk_order_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_order_item_price CHECK (unit_price >= 0),
    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id) REFERENCES products(product_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

ALTER TABLE products
    ADD COLUMN sku VARCHAR(50) UNIQUE;

INSERT INTO categories (category_name, description) VALUES
('Electronics', 'Electronic devices and accessories'),
('Books', 'Printed books and learning materials'),
('Home', 'Home and kitchen products');

INSERT INTO customers (full_name, email, phone) VALUES
('Maya Hassan', 'maya@example.com', '0501112233'),
('Omar Khaled', 'omar@example.com', '0502223344'),
('Lina Saleh', 'lina@example.com', '0503334455');

INSERT INTO products (
    category_id,
    product_name,
    description,
    price,
    stock_quantity,
    sku
) VALUES
(1, 'Wireless Headphones', 'Bluetooth over-ear headphones', 59.99, 25, 'ELEC-001'),
(1, 'USB-C Charger', 'Fast charging USB-C adapter', 19.50, 40, 'ELEC-002'),
(2, 'SQL for Beginners', 'Introduction to relational databases', 24.00, 18, 'BOOK-001'),
(3, 'Desk Lamp', 'Adjustable LED desk lamp', 32.75, 12, 'HOME-001');

INSERT INTO orders (customer_id, status) VALUES
(1, 'paid'),
(2, 'pending');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 59.99),
(1, 3, 2, 24.00),
(2, 2, 1, 19.50);

UPDATE products
SET stock_quantity = stock_quantity - 1
WHERE product_id = 1;

UPDATE products
SET stock_quantity = stock_quantity - 2
WHERE product_id = 3;

UPDATE products
SET stock_quantity = stock_quantity - 1
WHERE product_id = 2;

SELECT
    p.product_id,
    p.product_name,
    c.category_name,
    p.price,
    p.stock_quantity
FROM products AS p
INNER JOIN categories AS c ON c.category_id = p.category_id
WHERE p.is_active = TRUE
ORDER BY c.category_name, p.product_name;

SELECT
    c.category_name,
    COUNT(p.product_id) AS product_count,
    SUM(p.stock_quantity) AS units_in_stock
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.category_id
GROUP BY c.category_id, c.category_name
ORDER BY product_count DESC;

SELECT
    o.order_id,
    cu.full_name AS customer_name,
    o.order_date,
    o.status,
    SUM(oi.quantity * oi.unit_price) AS order_total
FROM orders AS o
INNER JOIN customers AS cu ON cu.customer_id = o.customer_id
INNER JOIN order_items AS oi ON oi.order_id = o.order_id
GROUP BY o.order_id, cu.full_name, o.order_date, o.status
ORDER BY o.order_date DESC;

SELECT
    p.product_name,
    SUM(oi.quantity) AS units_sold,
    SUM(oi.quantity * oi.unit_price) AS sales_total
FROM order_items AS oi
INNER JOIN products AS p ON p.product_id = oi.product_id
INNER JOIN orders AS o ON o.order_id = oi.order_id
WHERE o.status IN ('paid', 'shipped')
GROUP BY p.product_id, p.product_name
ORDER BY units_sold DESC;

DELIMITER $$

CREATE PROCEDURE place_order(
    IN p_customer_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_price DECIMAL(10, 2) DEFAULT NULL;
    DECLARE v_stock INT DEFAULT NULL;
    DECLARE v_order_id INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_quantity < 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Quantity must be at least one';
    END IF;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM customers
        WHERE customer_id = p_customer_id
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Customer not found';
    END IF;

    SELECT price, stock_quantity
    INTO v_price, v_stock
    FROM products
    WHERE product_id = p_product_id
      AND is_active = TRUE
    FOR UPDATE;

    IF v_price IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Product not found or inactive';
    ELSEIF v_stock < p_quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient product stock';
    ELSE
        INSERT INTO orders (customer_id, status)
        VALUES (p_customer_id, 'pending');

        SET v_order_id = LAST_INSERT_ID();

        INSERT INTO order_items (
            order_id,
            product_id,
            quantity,
            unit_price
        )
        VALUES (
            v_order_id,
            p_product_id,
            p_quantity,
            v_price
        );

        UPDATE products
        SET stock_quantity = stock_quantity - p_quantity
        WHERE product_id = p_product_id;

        COMMIT;

        SELECT v_order_id AS created_order_id;
    END IF;
END$$

DELIMITER ;

CREATE VIEW product_inventory AS
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    c.category_name,
    p.price,
    p.stock_quantity,
    p.is_active
FROM products AS p
INNER JOIN categories AS c ON c.category_id = p.category_id;

CREATE VIEW order_details AS
SELECT
    o.order_id,
    cu.full_name AS customer_name,
    cu.email,
    o.order_date,
    o.status,
    SUM(oi.quantity * oi.unit_price) AS order_total
FROM orders AS o
INNER JOIN customers AS cu ON cu.customer_id = o.customer_id
INNER JOIN order_items AS oi ON oi.order_id = o.order_id
GROUP BY
    o.order_id,
    cu.full_name,
    cu.email,
    o.order_date,
    o.status;

SELECT * FROM product_inventory;
SELECT * FROM order_details;
