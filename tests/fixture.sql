-- Synthetic data only. Types mirror db/schema.rb without production records.
SET NAMES utf8mb4;
SET time_zone = '+00:00';
CREATE TABLE init_markers (
  name VARCHAR(64) PRIMARY KEY,
  executions INT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO init_markers VALUES ('sql', 1);

CREATE TABLE customers (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  label VARCHAR(255) NOT NULL,
  email VARCHAR(255) NULL,
  UNIQUE KEY unique_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
CREATE TABLE orders (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  reference VARCHAR(255) NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  exchange_rate DECIMAL(28,25) NULL,
  note MEDIUMTEXT NULL,
  payload VARBINARY(64) NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 0,
  ordered_on DATE NULL,
  created_at DATETIME NOT NULL,
  observed_at TIMESTAMP NULL DEFAULT NULL,
  ratio DOUBLE NULL,
  UNIQUE KEY unique_reference (reference),
  KEY customer_created (customer_id, created_at),
  CONSTRAINT order_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
CREATE TABLE audit (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  previous_amount DECIMAL(15,2) NOT NULL,
  new_amount DECIMAL(15,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO customers (label, email) VALUES ('Élodie 東京 🌍', 'synthetic@example.invalid'), ('Null example', NULL);
INSERT INTO orders (customer_id, reference, amount, exchange_rate, note, payload, enabled, ordered_on, created_at, observed_at, ratio) VALUES
  (1, 'SYN-001', 1234.56, 0.1234567890123456789012345, 'UTF-8 text: café, 東京, 🌍', X'0001FF7F', 1, '2024-01-15', '2024-01-15 12:34:56', '2024-01-15 12:34:56', 0.125),
  (2, 'SYN-002', -0.01, NULL, NULL, NULL, 0, NULL, '2024-07-01 00:00:00', NULL, 0.3);

CREATE VIEW order_summary AS
  SELECT o.id, c.label, o.reference, o.amount FROM orders o JOIN customers c ON c.id = o.customer_id;
DELIMITER //
CREATE TRIGGER order_amount_audit AFTER UPDATE ON orders FOR EACH ROW
BEGIN
  INSERT INTO audit (order_id, previous_amount, new_amount) VALUES (NEW.id, OLD.amount, NEW.amount);
END//
CREATE PROCEDURE synthetic_count(OUT total INT)
BEGIN
  SELECT COUNT(*) INTO total FROM orders;
END//
DELIMITER ;
CREATE EVENT synthetic_future_event
  ON SCHEDULE EVERY 1 DAY STARTS '2030-01-01 00:00:00'
  ON COMPLETION PRESERVE ENABLE
  DO INSERT INTO init_markers (name, executions) VALUES ('event', 1)
     ON DUPLICATE KEY UPDATE executions = executions + 1;
UPDATE orders SET amount = 1234.57 WHERE id = 1;
