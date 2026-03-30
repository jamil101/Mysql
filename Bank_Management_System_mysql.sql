-- Bank Management System - MySQL Version

-- Drop existing tables if they exist
DROP TABLE IF EXISTS AUDIT_LOG;
DROP TABLE IF EXISTS NOTIFICATION;
DROP TABLE IF EXISTS ACCOUNT_STATEMENT;
DROP TABLE IF EXISTS BANK_TRANSACTION;
DROP TABLE IF EXISTS LOAN;
DROP TABLE IF EXISTS EMPLOYEE;
DROP TABLE IF EXISTS ACCOUNT;
DROP TABLE IF EXISTS BRANCH;
DROP TABLE IF EXISTS CUSTOMER;

-- Drop procedures if they exist
DROP PROCEDURE IF EXISTS sp_create_account;
DROP PROCEDURE IF EXISTS sp_deposit;
DROP PROCEDURE IF EXISTS sp_withdraw;
DROP PROCEDURE IF EXISTS sp_transfer;
DROP PROCEDURE IF EXISTS sp_generate_statement;
DROP PROCEDURE IF EXISTS sp_apply_interest;
DROP PROCEDURE IF EXISTS sp_calculate_emi;
DROP PROCEDURE IF EXISTS sp_send_notification;
DROP PROCEDURE IF EXISTS sp_close_account;

-- Drop functions if they exist
DROP FUNCTION IF EXISTS fn_get_balance;
DROP FUNCTION IF EXISTS fn_calc_interest;
DROP FUNCTION IF EXISTS fn_cust_worth;
DROP FUNCTION IF EXISTS fn_calc_emi;
DROP FUNCTION IF EXISTS fn_get_cust_summary;
DROP FUNCTION IF EXISTS fn_branch_rank;
DROP FUNCTION IF EXISTS fn_loan_eligibility;

-- Drop package if exists (MySQL doesn't have packages, so we'll skip)

-- Create tables
CREATE TABLE CUSTOMER (
    customer_id     INT PRIMARY KEY AUTO_INCREMENT,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(100) UNIQUE NOT NULL,
    phone           VARCHAR(15)  NOT NULL,
    address         VARCHAR(200),
    city            VARCHAR(50),
    zip_code        VARCHAR(10),
    date_of_birth   DATE,
    national_id     VARCHAR(20)  UNIQUE NOT NULL,
    occupation      VARCHAR(50),
    monthly_income  DECIMAL(10,2),
    created_date    DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_date    DATETIME
);

CREATE TABLE BRANCH (
    branch_id        INT PRIMARY KEY AUTO_INCREMENT,
    branch_code      VARCHAR(10)  UNIQUE NOT NULL,
    branch_name      VARCHAR(100) NOT NULL,
    branch_address   VARCHAR(200),
    city             VARCHAR(50),
    phone            VARCHAR(15),
    manager_name     VARCHAR(100),
    established_date DATE,
    status           VARCHAR(20) DEFAULT 'Active'
);

CREATE TABLE ACCOUNT (
    account_id      INT PRIMARY KEY AUTO_INCREMENT,
    customer_id     INT NOT NULL,
    branch_id       INT NOT NULL,
    account_number  VARCHAR(20) UNIQUE NOT NULL,
    account_type    VARCHAR(20) NOT NULL,
    balance         DECIMAL(15,2) DEFAULT 0,
    currency        VARCHAR(3)  DEFAULT 'BDT',
    interest_rate   DECIMAL(5,2),
    date_opened     DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_transaction DATETIME,
    status          VARCHAR(20) DEFAULT 'Active',
    FOREIGN KEY (customer_id) REFERENCES CUSTOMER(customer_id),
    FOREIGN KEY (branch_id) REFERENCES BRANCH(branch_id),
    CONSTRAINT chk_account_type CHECK (account_type IN ('Savings','Current','Fixed Deposit','Student')),
    CONSTRAINT chk_balance CHECK (balance >= 0)
);

CREATE TABLE EMPLOYEE (
    employee_id   INT PRIMARY KEY AUTO_INCREMENT,
    branch_id     INT NOT NULL,
    employee_code VARCHAR(20) UNIQUE NOT NULL,
    first_name    VARCHAR(50) NOT NULL,
    last_name     VARCHAR(50) NOT NULL,
    position      VARCHAR(50),
    salary        DECIMAL(10,2),
    hire_date     DATE,
    email         VARCHAR(100),
    phone         VARCHAR(15),
    status        VARCHAR(20) DEFAULT 'Active',
    FOREIGN KEY (branch_id) REFERENCES BRANCH(branch_id)
);

CREATE TABLE LOAN (
    loan_id       INT PRIMARY KEY AUTO_INCREMENT,
    customer_id   INT NOT NULL,
    account_id    INT NOT NULL,
    branch_id     INT NOT NULL,
    loan_number   VARCHAR(20) UNIQUE NOT NULL,
    loan_type     VARCHAR(30) NOT NULL,
    amount        DECIMAL(12,2) NOT NULL,
    interest_rate DECIMAL(5,2),
    start_date    DATE DEFAULT (CURDATE()),
    end_date      DATE,
    paid_amount   DECIMAL(12,2) DEFAULT 0,
    remaining_amt DECIMAL(12,2),
    status        VARCHAR(20) DEFAULT 'Active',
    FOREIGN KEY (customer_id) REFERENCES CUSTOMER(customer_id),
    FOREIGN KEY (account_id) REFERENCES ACCOUNT(account_id),
    FOREIGN KEY (branch_id) REFERENCES BRANCH(branch_id),
    CONSTRAINT chk_loan_type CHECK (loan_type IN ('Personal','Home','Auto','Education','Business')),
    CONSTRAINT chk_loan_status CHECK (status IN ('Active','Paid','Defaulted','Approved','Rejected'))
);

CREATE TABLE BANK_TRANSACTION (
    trans_id     INT PRIMARY KEY AUTO_INCREMENT,
    account_id   INT NOT NULL,
    trans_date   DATETIME DEFAULT CURRENT_TIMESTAMP,
    trans_type   VARCHAR(20) NOT NULL,
    amount       DECIMAL(12,2) NOT NULL,
    description  VARCHAR(200),
    reference_no VARCHAR(50),
    status       VARCHAR(20) DEFAULT 'Completed',
    created_by   VARCHAR(50) DEFAULT USER(),
    FOREIGN KEY (account_id) REFERENCES ACCOUNT(account_id),
    CONSTRAINT chk_trans_type CHECK (trans_type IN
        ('Deposit','Withdrawal','Transfer','Fee','Interest','Loan Payment'))
);

CREATE TABLE ACCOUNT_STATEMENT (
    statement_id      INT PRIMARY KEY AUTO_INCREMENT,
    account_id        INT NOT NULL,
    statement_date    DATETIME DEFAULT CURRENT_TIMESTAMP,
    opening_balance   DECIMAL(15,2),
    closing_balance   DECIMAL(15,2),
    total_deposit     DECIMAL(15,2),
    total_withdrawal  DECIMAL(15,2),
    generated_by      VARCHAR(50) DEFAULT USER(),
    FOREIGN KEY (account_id) REFERENCES ACCOUNT(account_id)
);

CREATE TABLE NOTIFICATION (
    notification_id   INT PRIMARY KEY AUTO_INCREMENT,
    customer_id       INT NOT NULL,
    notification_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    notification_type VARCHAR(30),
    message           VARCHAR(500),
    status            VARCHAR(20) DEFAULT 'Unread',
    FOREIGN KEY (customer_id) REFERENCES CUSTOMER(customer_id)
);

CREATE TABLE AUDIT_LOG (
    audit_id     INT PRIMARY KEY AUTO_INCREMENT,
    table_name   VARCHAR(50),
    action_type  VARCHAR(20),
    record_id    INT,
    old_value    TEXT,
    new_value    TEXT,
    changed_by   VARCHAR(50) DEFAULT USER(),
    changed_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Create Views
CREATE OR REPLACE VIEW v_customer_portfolio AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    c.email,
    c.phone,
    COUNT(DISTINCT a.account_id) AS total_accounts,
    COALESCE(SUM(a.balance), 0) AS total_balance,
    COUNT(DISTINCT l.loan_id) AS total_loans,
    COALESCE(SUM(l.remaining_amt), 0) AS total_loan_balance,
    COALESCE(SUM(a.balance), 0) - COALESCE(SUM(l.remaining_amt), 0) AS net_worth
FROM CUSTOMER c
LEFT JOIN ACCOUNT a ON c.customer_id = a.customer_id AND a.status = 'Active'
LEFT JOIN LOAN l ON c.customer_id = l.customer_id AND l.status = 'Active'
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.phone;

CREATE OR REPLACE VIEW v_branch_dashboard AS
SELECT
    b.branch_id,
    b.branch_name,
    b.city,
    b.manager_name,
    COUNT(DISTINCT e.employee_id) AS employee_count,
    COUNT(DISTINCT a.account_id) AS account_count,
    COALESCE(SUM(a.balance), 0) AS total_deposits,
    COUNT(DISTINCT l.loan_id) AS loan_count,
    COALESCE(SUM(l.amount), 0) AS total_loans,
    ROUND(COALESCE(SUM(a.balance), 0) / NULLIF(COUNT(DISTINCT a.account_id), 0), 2) AS avg_account_balance
FROM BRANCH b
LEFT JOIN EMPLOYEE e ON b.branch_id = e.branch_id
LEFT JOIN ACCOUNT a ON b.branch_id = a.branch_id
LEFT JOIN LOAN l ON b.branch_id = l.branch_id
GROUP BY b.branch_id, b.branch_name, b.city, b.manager_name;

CREATE OR REPLACE VIEW v_monthly_trans_summary AS
SELECT
    DATE_FORMAT(t.trans_date, '%Y-%m') AS month,
    a.account_type,
    COUNT(t.trans_id) AS transaction_count,
    SUM(CASE WHEN t.trans_type = 'Deposit' THEN t.amount ELSE 0 END) AS total_deposits,
    SUM(CASE WHEN t.trans_type = 'Withdrawal' THEN ABS(t.amount) ELSE 0 END) AS total_withdrawals,
    SUM(CASE WHEN t.trans_type = 'Transfer' THEN ABS(t.amount) ELSE 0 END) AS total_transfers,
    COUNT(DISTINCT a.account_id) AS active_accounts
FROM BANK_TRANSACTION t
JOIN ACCOUNT a ON t.account_id = a.account_id
WHERE t.status = 'Completed'
GROUP BY DATE_FORMAT(t.trans_date, '%Y-%m'), a.account_type;

CREATE OR REPLACE VIEW v_high_value_customers AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.email,
    c.phone,
    c.occupation,
    COALESCE(SUM(a.balance), 0) AS total_balance,
    COALESCE(SUM(l.amount), 0) AS total_loan,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(a.balance), 0) DESC) AS rank_by_balance
FROM CUSTOMER c
LEFT JOIN ACCOUNT a ON c.customer_id = a.customer_id AND a.status = 'Active'
LEFT JOIN LOAN l ON c.customer_id = l.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.phone, c.occupation
HAVING COALESCE(SUM(a.balance), 0) > 100000;

CREATE OR REPLACE VIEW v_loan_schedule AS
SELECT
    l.loan_id,
    l.loan_number,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    l.loan_type,
    l.amount AS principal,
    l.interest_rate,
    l.start_date,
    l.end_date,
    TIMESTAMPDIFF(MONTH, l.start_date, l.end_date) AS tenure_months,
    l.remaining_amt,
    ROUND(
        l.amount * (l.interest_rate / 1200) *
        POWER(1 + (l.interest_rate / 1200), TIMESTAMPDIFF(MONTH, l.start_date, l.end_date)) /
        (POWER(1 + (l.interest_rate / 1200), TIMESTAMPDIFF(MONTH, l.start_date, l.end_date)) - 1)
    , 2) AS monthly_emi,
    CASE
        WHEN l.remaining_amt <= 0 THEN 'Fully Paid'
        WHEN l.end_date < CURDATE() THEN 'Overdue'
        ELSE 'Active'
    END AS repayment_status
FROM LOAN l
JOIN CUSTOMER c ON l.customer_id = c.customer_id
WHERE l.status != 'Paid';

-- Create Procedures
DELIMITER //

CREATE PROCEDURE sp_create_account (
    IN p_cust_id INT,
    IN p_branch_id INT,
    IN p_acc_type VARCHAR(20),
    IN p_amount DECIMAL(12,2),
    OUT p_acc_id INT,
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_acc_number VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_acc_id = NULL;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    INSERT INTO ACCOUNT (customer_id, branch_id, account_number, account_type, balance, date_opened, status)
    VALUES (p_cust_id, p_branch_id, CONCAT('ACC', LAST_INSERT_ID() + 5000), p_acc_type, p_amount, NOW(), 'Active');
    
    SET p_acc_id = LAST_INSERT_ID();
    SET v_acc_number = CONCAT('ACC', p_acc_id);
    
    UPDATE ACCOUNT SET account_number = v_acc_number WHERE account_id = p_acc_id;
    
    IF p_amount > 0 THEN
        INSERT INTO BANK_TRANSACTION (account_id, trans_type, amount, description, reference_no)
        VALUES (p_acc_id, 'Deposit', p_amount, 'Account opening deposit', CONCAT('OPEN_', p_acc_id));
    END IF;
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Account ', v_acc_number, ' created');
END//

CREATE PROCEDURE sp_deposit (
    IN p_acc_id INT,
    IN p_amount DECIMAL(12,2),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_acc_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    IF p_amount <= 0 THEN
        SET p_status = 'ERROR: Deposit amount must be positive';
        ROLLBACK;
        RETURN;
    END IF;
    
    SELECT status INTO v_acc_status FROM ACCOUNT WHERE account_id = p_acc_id;
    
    IF v_acc_status != 'Active' THEN
        SET p_status = 'ERROR: Account is not active';
        ROLLBACK;
        RETURN;
    END IF;
    
    UPDATE ACCOUNT SET balance = balance + p_amount WHERE account_id = p_acc_id;
    
    INSERT INTO BANK_TRANSACTION (account_id, trans_type, amount, description)
    VALUES (p_acc_id, 'Deposit', p_amount, 'Cash deposit');
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Deposited ', p_amount, ' to account ', p_acc_id);
END//

CREATE PROCEDURE sp_withdraw (
    IN p_acc_id INT,
    IN p_amount DECIMAL(12,2),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_acc_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    IF p_amount <= 0 THEN
        SET p_status = 'ERROR: Withdrawal amount must be positive';
        ROLLBACK;
        RETURN;
    END IF;
    
    SELECT balance, status INTO v_balance, v_acc_status
    FROM ACCOUNT WHERE account_id = p_acc_id;
    
    IF v_acc_status != 'Active' THEN
        SET p_status = 'ERROR: Account is not active';
        ROLLBACK;
        RETURN;
    END IF;
    
    IF v_balance < p_amount THEN
        SET p_status = CONCAT('ERROR: Insufficient funds. Balance: ', v_balance);
        ROLLBACK;
        RETURN;
    END IF;
    
    UPDATE ACCOUNT SET balance = balance - p_amount WHERE account_id = p_acc_id;
    
    INSERT INTO BANK_TRANSACTION (account_id, trans_type, amount, description)
    VALUES (p_acc_id, 'Withdrawal', -p_amount, 'Cash withdrawal');
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Withdrawn ', p_amount, ' from account ', p_acc_id);
END//

CREATE PROCEDURE sp_transfer (
    IN p_from_acc INT,
    IN p_to_acc INT,
    IN p_amount DECIMAL(12,2),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_from_balance DECIMAL(15,2);
    DECLARE v_from_status VARCHAR(20);
    DECLARE v_to_status VARCHAR(20);
    DECLARE v_ref VARCHAR(50);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    IF p_amount <= 0 THEN
        SET p_status = 'ERROR: Transfer amount must be positive';
        ROLLBACK;
        RETURN;
    END IF;
    
    IF p_from_acc = p_to_acc THEN
        SET p_status = 'ERROR: Source and destination accounts must differ';
        ROLLBACK;
        RETURN;
    END IF;
    
    SELECT balance, status INTO v_from_balance, v_from_status
    FROM ACCOUNT WHERE account_id = p_from_acc;
    
    SELECT status INTO v_to_status
    FROM ACCOUNT WHERE account_id = p_to_acc;
    
    IF v_from_status != 'Active' THEN
        SET p_status = 'ERROR: Source account is not active';
        ROLLBACK;
        RETURN;
    END IF;
    
    IF v_to_status != 'Active' THEN
        SET p_status = 'ERROR: Destination account is not active';
        ROLLBACK;
        RETURN;
    END IF;
    
    IF v_from_balance < p_amount THEN
        SET p_status = CONCAT('ERROR: Insufficient funds. Balance: ', v_from_balance);
        ROLLBACK;
        RETURN;
    END IF;
    
    SET v_ref = CONCAT('TRF_', p_from_acc, '_', p_to_acc, '_', DATE_FORMAT(NOW(), '%Y%m%d'));
    
    UPDATE ACCOUNT SET balance = balance - p_amount WHERE account_id = p_from_acc;
    UPDATE ACCOUNT SET balance = balance + p_amount WHERE account_id = p_to_acc;
    
    INSERT INTO BANK_TRANSACTION (account_id, trans_type, amount, description, reference_no)
    VALUES (p_from_acc, 'Transfer', -p_amount, CONCAT('Transfer to account ', p_to_acc), v_ref);
    
    INSERT INTO BANK_TRANSACTION (account_id, trans_type, amount, description, reference_no)
    VALUES (p_to_acc, 'Transfer', p_amount, CONCAT('Transfer from account ', p_from_acc), v_ref);
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Transferred ', p_amount, ' from ', p_from_acc, ' to ', p_to_acc);
END//

CREATE PROCEDURE sp_generate_statement (
    IN p_account_id INT,
    IN p_statement_date DATE,
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_opening_bal DECIMAL(15,2);
    DECLARE v_closing_bal DECIMAL(15,2);
    DECLARE v_total_deposit DECIMAL(15,2);
    DECLARE v_total_withdrawal DECIMAL(15,2);
    DECLARE v_statement_date DATE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    IF p_statement_date IS NULL THEN
        SET v_statement_date = CURDATE();
    ELSE
        SET v_statement_date = p_statement_date;
    END IF;
    
    SELECT COALESCE(SUM(CASE WHEN trans_date < DATE_FORMAT(v_statement_date, '%Y-%m-01')
                        THEN amount ELSE 0 END), 0)
    INTO v_opening_bal
    FROM BANK_TRANSACTION
    WHERE account_id = p_account_id AND status = 'Completed';
    
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_deposit
    FROM BANK_TRANSACTION
    WHERE account_id = p_account_id
      AND trans_type IN ('Deposit', 'Transfer')
      AND amount > 0
      AND trans_date BETWEEN DATE_FORMAT(v_statement_date, '%Y-%m-01') AND v_statement_date;
    
    SELECT COALESCE(SUM(ABS(amount)), 0)
    INTO v_total_withdrawal
    FROM BANK_TRANSACTION
    WHERE account_id = p_account_id
      AND trans_type IN ('Withdrawal', 'Transfer')
      AND amount < 0
      AND trans_date BETWEEN DATE_FORMAT(v_statement_date, '%Y-%m-01') AND v_statement_date;
    
    SELECT balance INTO v_closing_bal
    FROM ACCOUNT WHERE account_id = p_account_id;
    
    INSERT INTO ACCOUNT_STATEMENT
        (account_id, statement_date, opening_balance, closing_balance, total_deposit, total_withdrawal)
    VALUES
        (p_account_id, v_statement_date, v_opening_bal, v_closing_bal, v_total_deposit, v_total_withdrawal);
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Statement generated for account ', p_account_id);
END//

CREATE PROCEDURE sp_apply_interest (
    IN p_month VARCHAR(7),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_account_id INT;
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_account_type VARCHAR(20);
    DECLARE v_interest_rate DECIMAL(5,2);
    DECLARE v_interest DECIMAL(15,2);
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_month VARCHAR(7);
    DECLARE cur_accounts CURSOR FOR
        SELECT account_id, balance, account_type, interest_rate
        FROM ACCOUNT
        WHERE status = 'Active'
          AND account_type IN ('Savings', 'Fixed Deposit');
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    IF p_month IS NULL THEN
        SET v_month = DATE_FORMAT(NOW(), '%Y-%m');
    ELSE
        SET v_month = p_month;
    END IF;
    
    OPEN cur_accounts;
    
    read_loop: LOOP
        FETCH cur_accounts INTO v_account_id, v_balance, v_account_type, v_interest_rate;
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        SET v_interest_rate = CASE v_account_type
            WHEN 'Savings' THEN COALESCE(v_interest_rate, 4.0)
            WHEN 'Fixed Deposit' THEN COALESCE(v_interest_rate, 7.5)
            ELSE 0
        END;
        
        SET v_interest = (v_balance * v_interest_rate) / (12 * 100);
        
        IF v_interest > 0 THEN
            UPDATE ACCOUNT SET balance = balance + v_interest
            WHERE account_id = v_account_id;
            
            INSERT INTO BANK_TRANSACTION
                (account_id, trans_type, amount, description, reference_no)
            VALUES
                (v_account_id, 'Interest', v_interest,
                 CONCAT('Monthly interest for ', v_month),
                 CONCAT('INT_', v_month, '_', v_account_id));
            
            SET v_count = v_count + 1;
        END IF;
    END LOOP;
    
    CLOSE cur_accounts;
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Interest applied to ', v_count, ' accounts');
END//

CREATE PROCEDURE sp_calculate_emi (
    IN p_loan_id INT,
    OUT p_emi_amount DECIMAL(15,2),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_principal DECIMAL(15,2);
    DECLARE v_rate DECIMAL(5,2);
    DECLARE v_months INT;
    DECLARE v_monthly_rate DECIMAL(15,6);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_emi_amount = 0;
        SET p_status = CONCAT('ERROR: ', 'Calculation failed');
    END;
    
    SELECT amount, interest_rate,
           TIMESTAMPDIFF(MONTH, start_date, end_date)
    INTO v_principal, v_rate, v_months
    FROM LOAN WHERE loan_id = p_loan_id;
    
    SET v_monthly_rate = v_rate / (12 * 100);
    
    SET p_emi_amount = ROUND(
        v_principal * v_monthly_rate *
        POWER(1 + v_monthly_rate, v_months) /
        (POWER(1 + v_monthly_rate, v_months) - 1)
    , 2);
    
    SET p_status = 'SUCCESS: EMI calculated';
END//

CREATE PROCEDURE sp_send_notification (
    IN p_customer_id INT,
    IN p_notification_type VARCHAR(30),
    IN p_message VARCHAR(500),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_cust_exists INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    SELECT COUNT(*) INTO v_cust_exists
    FROM CUSTOMER WHERE customer_id = p_customer_id;
    
    IF v_cust_exists = 0 THEN
        SET p_status = 'ERROR: Customer not found';
        ROLLBACK;
        RETURN;
    END IF;
    
    INSERT INTO NOTIFICATION (customer_id, notification_type, message)
    VALUES (p_customer_id, p_notification_type, p_message);
    
    COMMIT;
    SET p_status = 'SUCCESS: Notification sent';
END//

CREATE PROCEDURE sp_close_account (
    IN p_account_id INT,
    IN p_reason VARCHAR(200),
    OUT p_status VARCHAR(200)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_acc_status VARCHAR(20);
    DECLARE v_customer_id INT;
    DECLARE v_notif_status VARCHAR(200);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: ', 'Transaction failed');
    END;
    
    START TRANSACTION;
    
    SELECT balance, status, customer_id
    INTO v_balance, v_acc_status, v_customer_id
    FROM ACCOUNT WHERE account_id = p_account_id;
    
    IF v_acc_status = 'Closed' THEN
        SET p_status = 'ERROR: Account already closed';
        ROLLBACK;
        RETURN;
    END IF;
    
    IF v_balance > 0 THEN
        SET p_status = CONCAT('ERROR: Account has balance of ', v_balance, '. Please withdraw first');
        ROLLBACK;
        RETURN;
    END IF;
    
    UPDATE ACCOUNT SET status = 'Closed' WHERE account_id = p_account_id;
    
    CALL sp_send_notification(
        v_customer_id,
        'Account Closed',
        CONCAT('Your account ', p_account_id, ' has been closed. Reason: ', p_reason),
        v_notif_status
    );
    
    COMMIT;
    SET p_status = CONCAT('SUCCESS: Account ', p_account_id, ' closed successfully');
END//

-- Create Functions
CREATE FUNCTION fn_get_balance (p_acc_id INT) 
RETURNS DECIMAL(15,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    
    SELECT balance INTO v_balance FROM ACCOUNT WHERE account_id = p_acc_id;
    RETURN v_balance;
END//

CREATE FUNCTION fn_calc_interest (p_acc_id INT, p_days INT) 
RETURNS DECIMAL(15,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_type VARCHAR(20);
    DECLARE v_rate DECIMAL(5,2);
    
    SELECT balance, account_type INTO v_balance, v_type
    FROM ACCOUNT WHERE account_id = p_acc_id;
    
    SET v_rate = CASE v_type
        WHEN 'Savings' THEN 4.0
        WHEN 'Fixed Deposit' THEN 7.5
        ELSE 0
    END;
    
    RETURN ROUND(v_balance + (v_balance * v_rate * p_days) / 36500, 2);
END//

CREATE FUNCTION fn_cust_worth (p_cust_id INT) 
RETURNS DECIMAL(15,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_bal DECIMAL(15,2);
    DECLARE v_total_loan DECIMAL(15,2);
    
    SELECT COALESCE(SUM(balance), 0) INTO v_total_bal
    FROM ACCOUNT WHERE customer_id = p_cust_id;
    
    SELECT COALESCE(SUM(remaining_amt), 0) INTO v_total_loan
    FROM LOAN WHERE customer_id = p_cust_id AND status != 'Paid';
    
    RETURN ROUND(v_total_bal - v_total_loan, 2);
END//

CREATE FUNCTION fn_calc_emi (
    p_principal DECIMAL(15,2),
    p_rate DECIMAL(5,2),
    p_months INT
) 
RETURNS DECIMAL(15,2)
DETERMINISTIC
BEGIN
    DECLARE v_monthly_rate DECIMAL(15,6);
    
    IF p_principal <= 0 OR p_rate <= 0 OR p_months <= 0 THEN
        RETURN NULL;
    END IF;
    
    SET v_monthly_rate = p_rate / (12 * 100);
    RETURN ROUND(
        p_principal * v_monthly_rate *
        POWER(1 + v_monthly_rate, p_months) /
        (POWER(1 + v_monthly_rate, p_months) - 1)
    , 2);
END//

CREATE FUNCTION fn_get_cust_summary (p_cust_id INT) 
RETURNS VARCHAR(500)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_deposit DECIMAL(15,2);
    DECLARE v_total_withdrawal DECIMAL(15,2);
    DECLARE v_account_count INT;
    DECLARE v_loan_count INT;
    
    SELECT
        COALESCE(SUM(CASE WHEN t.trans_type = 'Deposit' THEN t.amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN t.trans_type = 'Withdrawal' THEN ABS(t.amount) ELSE 0 END), 0)
    INTO v_total_deposit, v_total_withdrawal
    FROM BANK_TRANSACTION t
    JOIN ACCOUNT a ON t.account_id = a.account_id
    WHERE a.customer_id = p_cust_id;
    
    SELECT COUNT(*) INTO v_account_count FROM ACCOUNT WHERE customer_id = p_cust_id;
    SELECT COUNT(*) INTO v_loan_count FROM LOAN WHERE customer_id = p_cust_id;
    
    RETURN CONCAT('Total Deposit: ', v_total_deposit,
           ', Total Withdrawal: ', v_total_withdrawal,
           ', Accounts: ', v_account_count,
           ', Loans: ', v_loan_count);
END//

CREATE FUNCTION fn_branch_rank (p_branch_id INT) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_rank INT;
    
    SELECT ranked.branch_rank
    INTO v_rank
    FROM (
        SELECT
            b.branch_id,
            RANK() OVER (ORDER BY COALESCE(SUM(a.balance), 0) DESC) AS branch_rank
        FROM BRANCH b
        LEFT JOIN ACCOUNT a ON b.branch_id = a.branch_id
        GROUP BY b.branch_id
    ) ranked
    WHERE ranked.branch_id = p_branch_id;
    
    RETURN v_rank;
END//

CREATE FUNCTION fn_loan_eligibility (
    p_cust_id INT,
    p_requested_loan DECIMAL(15,2)
) 
RETURNS VARCHAR(500)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_monthly_income DECIMAL(10,2);
    DECLARE v_existing_loan DECIMAL(15,2);
    DECLARE v_eligibility VARCHAR(50);
    
    SELECT monthly_income INTO v_monthly_income
    FROM CUSTOMER WHERE customer_id = p_cust_id;
    
    SELECT COALESCE(SUM(remaining_amt), 0) INTO v_existing_loan
    FROM LOAN WHERE customer_id = p_cust_id AND status = 'Active';
    
    IF v_monthly_income >= 30000
       AND (v_existing_loan + p_requested_loan) <= (v_monthly_income * 5) THEN
        SET v_eligibility = 'Eligible';
    ELSE
        SET v_eligibility = 'Not Eligible';
    END IF;
    
    RETURN CONCAT(v_eligibility,
           ' - Monthly Income: ', v_monthly_income,
           ', Existing Loan: ', v_existing_loan);
END//

-- Create Triggers
CREATE TRIGGER trg_update_last_trans
AFTER INSERT ON BANK_TRANSACTION
FOR EACH ROW
BEGIN
    UPDATE ACCOUNT SET last_transaction = NOW()
    WHERE account_id = NEW.account_id;
END//

CREATE TRIGGER trg_audit_account
AFTER UPDATE ON ACCOUNT
FOR EACH ROW
BEGIN
    INSERT INTO AUDIT_LOG
        (table_name, action_type, record_id, old_value, new_value)
    VALUES
        ('ACCOUNT', 'UPDATE', NEW.account_id,
         CONCAT('Balance: ', OLD.balance, ', Status: ', OLD.status),
         CONCAT('Balance: ', NEW.balance, ', Status: ', NEW.status));
END//

DELIMITER ;

-- Insert sample data
INSERT INTO BRANCH (branch_id, branch_code, branch_name, branch_address, city, phone, manager_name, established_date, status) 
VALUES (1,'BR001','Main Branch',  '123 Main Street','Dhaka','02-1234567','Mr. Rahman', '2010-01-01','Active');
INSERT INTO BRANCH (branch_id, branch_code, branch_name, branch_address, city, phone, manager_name, established_date, status) 
VALUES (2,'BR002','Uttara Branch','45/A Sector 7',  'Dhaka','02-7654321','Ms. Khan',   '2015-03-15','Active');
INSERT INTO BRANCH (branch_id, branch_code, branch_name, branch_address, city, phone, manager_name, established_date, status) 
VALUES (3,'BR003','Gulshan Branch','Road 27',       'Dhaka','02-9876543','Mr. Hossain','2018-07-20','Active');

INSERT INTO CUSTOMER (customer_id, first_name, last_name, email, phone, address, city, zip_code, date_of_birth, national_id, occupation, monthly_income, created_date) 
VALUES (1,'Rahim',  'Ahmed', 'rahim.ahmed@email.com',  '01712345678','House 12, Road 5',    'Dhaka','1205','1985-05-15','1234567890123','Business',150000,NOW());
INSERT INTO CUSTOMER (customer_id, first_name, last_name, email, phone, address, city, zip_code, date_of_birth, national_id, occupation, monthly_income, created_date) 
VALUES (2,'Karima', 'Begum', 'karima.begum@email.com', '01887654321','Flat 3B, Mirpur DOHS','Dhaka','1216','1990-08-22','9876543210987','Service', 80000, NOW());
INSERT INTO CUSTOMER (customer_id, first_name, last_name, email, phone, address, city, zip_code, date_of_birth, national_id, occupation, monthly_income, created_date) 
VALUES (3,'Shahid', 'Ali',   'shahid.ali@email.com',   '01911223344','56/A, Mohammadpur',  'Dhaka','1207','1982-11-30','4567890123456','Business',120000,NOW());
INSERT INTO CUSTOMER (customer_id, first_name, last_name, email, phone, address, city, zip_code, date_of_birth, national_id, occupation, monthly_income, created_date) 
VALUES (4,'Nasrin', 'Akter', 'nasrin.akter@email.com', '01555667788','23/B, Banasree',     'Dhaka','1219','1995-03-10','7890123456789','Student', 25000, NOW());
INSERT INTO CUSTOMER (customer_id, first_name, last_name, email, phone, address, city, zip_code, date_of_birth, national_id, occupation, monthly_income, created_date) 
VALUES (5,'Faruk',  'Hossain','faruk.hossain@email.com','01699887766','102, Shantinagar',  'Dhaka','1217','1988-07-19','2345678901234','Service', 95000, NOW());

INSERT INTO ACCOUNT (account_id, customer_id, branch_id, account_number, account_type, balance, currency, interest_rate, date_opened, status) 
VALUES (1001,1,1,'ACC1001','Savings',      250000,'BDT',4.0, '2020-01-10','Active');
INSERT INTO ACCOUNT (account_id, customer_id, branch_id, account_number, account_type, balance, currency, interest_rate, date_opened, status) 
VALUES (1002,2,1,'ACC1002','Current',     1500000,'BDT',0,   '2021-03-15','Active');
INSERT INTO ACCOUNT (account_id, customer_id, branch_id, account_number, account_type, balance, currency, interest_rate, date_opened, status) 
VALUES (1003,3,2,'ACC1003','Savings',       75000,'BDT',4.0, '2022-05-20','Active');
INSERT INTO ACCOUNT (account_id, customer_id, branch_id, account_number, account_type, balance, currency, interest_rate, date_opened, status) 
VALUES (1004,4,3,'ACC1004','Fixed Deposit', 500000,'BDT',7.5, '2023-01-05','Active');
INSERT INTO ACCOUNT (account_id, customer_id, branch_id, account_number, account_type, balance, currency, interest_rate, date_opened, status) 
VALUES (1005,5,2,'ACC1005','Student',      125000,'BDT',3.5, '2023-06-12','Active');

INSERT INTO EMPLOYEE (employee_id, branch_id, employee_code, first_name, last_name, position, salary, hire_date, email, phone, status) 
VALUES (101,1,'EMP001','Aminul',  'Islam',   'Manager',    85000,'2012-06-01','aminul@bank.com',  '01711111111','Active');
INSERT INTO EMPLOYEE (employee_id, branch_id, employee_code, first_name, last_name, position, salary, hire_date, email, phone, status) 
VALUES (102,1,'EMP002','Shamima', 'Rahman',  'Cashier',    45000,'2018-04-15','shamima@bank.com', '01722222222','Active');
INSERT INTO EMPLOYEE (employee_id, branch_id, employee_code, first_name, last_name, position, salary, hire_date, email, phone, status) 
VALUES (103,2,'EMP003','Imran',   'Hasan',   'Loan Officer',55000,'2019-02-10','imran@bank.com',  '01833333333','Active');
INSERT INTO EMPLOYEE (employee_id, branch_id, employee_code, first_name, last_name, position, salary, hire_date, email, phone, status) 
VALUES (104,3,'EMP004','Tahmina', 'Sultana', 'Accountant', 52000,'2020-01-20','tahmina@bank.com','01944444444','Active');

INSERT INTO LOAN (loan_id, customer_id, account_id, branch_id, loan_number, loan_type, amount, interest_rate, start_date, end_date, paid_amount, remaining_amt, status) 
VALUES (5001,1,1001,1,'LN5001','Home',    3000000,9.5, '2020-02-01','2030-02-01',500000,2500000,'Active');
INSERT INTO LOAN (loan_id, customer_id, account_id, branch_id, loan_number, loan_type, amount, interest_rate, start_date, end_date, paid_amount, remaining_amt, status) 
VALUES (5002,2,1002,1,'LN5002','Personal', 500000,12.0,'2022-01-15','2025-01-15',200000, 300000,'Active');
INSERT INTO LOAN (loan_id, customer_id, account_id, branch_id, loan_number, loan_type, amount, interest_rate, start_date, end_date, paid_amount, remaining_amt, status) 
VALUES (5003,3,1003,2,'LN5003','Auto',     800000,10.5,'2023-03-10','2028-03-10', 50000, 750000,'Active');

INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20001,1001,'2024-01-15','Deposit',   50000, 'Salary deposit',        'TRX001','Completed',USER());
INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20002,1001,'2024-01-20','Withdrawal',-10000,'ATM withdrawal',         'TRX002','Completed',USER());
INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20003,1002,'2024-01-18','Deposit',  200000, 'Cheque deposit',         'TRX003','Completed',USER());
INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20004,1002,'2024-01-22','Transfer', -50000, 'Transfer to savings',    'TRX004','Completed',USER());
INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20005,1003,'2024-01-25','Deposit',   25000, 'Cash deposit',           'TRX005','Completed',USER());
INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20006,1004,'2024-02-01','Interest',   3000, 'Interest credited',      'INT001','Completed',USER());
INSERT INTO BANK_TRANSACTION (trans_id, account_id, trans_date, trans_type, amount, description, reference_no, status, created_by) 
VALUES (20007,1005,'2024-02-05','Deposit',   10000, 'Cash deposit',           'TRX006','Completed',USER());

-- Reset auto_increment values
ALTER TABLE CUSTOMER AUTO_INCREMENT = 6;
ALTER TABLE BRANCH AUTO_INCREMENT = 4;
ALTER TABLE ACCOUNT AUTO_INCREMENT = 5000;
ALTER TABLE EMPLOYEE AUTO_INCREMENT = 105;
ALTER TABLE LOAN AUTO_INCREMENT = 5004;
ALTER TABLE BANK_TRANSACTION AUTO_INCREMENT = 20008;
ALTER TABLE ACCOUNT_STATEMENT AUTO_INCREMENT = 1000;
ALTER TABLE NOTIFICATION AUTO_INCREMENT = 1000;
ALTER TABLE AUDIT_LOG AUTO_INCREMENT = 1000;

-- Display sample data
SELECT * FROM v_customer_portfolio ORDER BY net_worth DESC;

SELECT * FROM v_branch_dashboard;

SELECT * FROM v_monthly_trans_summary ORDER BY month DESC, account_type LIMIT 10;

SELECT * FROM v_high_value_customers ORDER BY rank_by_balance LIMIT 5;

SELECT * FROM v_loan_schedule;

-- Test procedures
DELIMITER //
CREATE PROCEDURE test_generate_statement()
BEGIN
    DECLARE v_status VARCHAR(200);
    CALL sp_generate_statement(1001, CURDATE(), v_status);
    SELECT v_status AS 'Generate Statement Result';
END//

CREATE PROCEDURE test_apply_interest()
BEGIN
    DECLARE v_status VARCHAR(200);
    CALL sp_apply_interest(DATE_FORMAT(NOW(), '%Y-%m'), v_status);
    SELECT v_status AS 'Apply Interest Result';
END//

CREATE PROCEDURE test_calculate_emi()
BEGIN
    DECLARE v_emi DECIMAL(15,2);
    DECLARE v_status VARCHAR(200);
    CALL sp_calculate_emi(5001, v_emi, v_status);
    SELECT v_status AS 'EMI Status', v_emi AS 'EMI Amount';
END//

CREATE PROCEDURE test_loan_eligibility()
BEGIN
    SELECT customer_id,
           CONCAT(first_name, ' ', last_name) AS name,
           monthly_income,
           fn_loan_eligibility(customer_id, 500000) AS eligibility_status
    FROM CUSTOMER
    LIMIT 5;
END//

CREATE PROCEDURE test_branch_rank()
BEGIN
    SELECT branch_id, branch_name, fn_branch_rank(branch_id) AS rank
    FROM BRANCH
    ORDER BY rank;
END//

CREATE PROCEDURE test_deposit()
BEGIN
    DECLARE v_status VARCHAR(200);
    CALL sp_deposit(1003, 5000, v_status);
    SELECT v_status AS 'Deposit Result';
END//

CREATE PROCEDURE test_withdraw()
BEGIN
    DECLARE v_status VARCHAR(200);
    CALL sp_withdraw(1003, 2000, v_status);
    SELECT v_status AS 'Withdraw Result';
END//

CREATE PROCEDURE test_transfer()
BEGIN
    DECLARE v_status VARCHAR(200);
    CALL sp_transfer(1001, 1003, 10000, v_status);
    SELECT v_status AS 'Transfer Result';
END//

CREATE PROCEDURE test_all_operations()
BEGIN
    CALL test_generate_statement();
    CALL test_apply_interest();
    CALL test_calculate_emi();
    CALL test_loan_eligibility();
    CALL test_branch_rank();
    CALL test_deposit();
    CALL test_withdraw();
    CALL test_transfer();
END//
DELIMITER ;

-- Run the test operations
CALL test_all_operations();

-- Check row counts
SELECT 'CUSTOMER' AS Table_Name, COUNT(*) AS Row_Count FROM CUSTOMER UNION ALL
SELECT 'BRANCH', COUNT(*) FROM BRANCH UNION ALL
SELECT 'ACCOUNT', COUNT(*) FROM ACCOUNT UNION ALL
SELECT 'EMPLOYEE', COUNT(*) FROM EMPLOYEE UNION ALL
SELECT 'LOAN', COUNT(*) FROM LOAN UNION ALL
SELECT 'BANK_TRANSACTION', COUNT(*) FROM BANK_TRANSACTION UNION ALL
SELECT 'ACCOUNT_STATEMENT', COUNT(*) FROM ACCOUNT_STATEMENT UNION ALL
SELECT 'NOTIFICATION', COUNT(*) FROM NOTIFICATION UNION ALL
SELECT 'AUDIT_LOG', COUNT(*) FROM AUDIT_LOG;

-- Clean up test procedures
DROP PROCEDURE IF EXISTS test_generate_statement;
DROP PROCEDURE IF EXISTS test_apply_interest;
DROP PROCEDURE IF EXISTS test_calculate_emi;
DROP PROCEDURE IF EXISTS test_loan_eligibility;
DROP PROCEDURE IF EXISTS test_branch_rank;
DROP PROCEDURE IF EXISTS test_deposit;
DROP PROCEDURE IF EXISTS test_withdraw;
DROP PROCEDURE IF EXISTS test_transfer;
DROP PROCEDURE IF EXISTS test_all_operations;