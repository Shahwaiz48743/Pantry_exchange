-- 1) Create DB
CREATE DATABASE pantry_exchange_db;
 

USE pantry_exchange_db;

-- For consistency & safety


-- 2) Core geo & household structure
CREATE TABLE zones (
  zone_id BIGINT NOT NULL IDENTITY(1,1),  -- auto increment
  name NVARCHAR(120) NOT NULL,
  center_lat DECIMAL(9,6) NULL,
  center_lng DECIMAL(9,6) NULL,
  CONSTRAINT pk_zones PRIMARY KEY (zone_id),
  CONSTRAINT uq_zones_name UNIQUE (name)
);

CREATE TABLE households (
  household_id BIGINT NOT NULL IDENTITY(1,1),
  address NVARCHAR(255) NULL,
  geo_lat DECIMAL(9,6) NULL,
  geo_lng DECIMAL(9,6) NULL,
  zone_id BIGINT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_households PRIMARY KEY (household_id),
  CONSTRAINT fk_households_zone
      FOREIGN KEY (zone_id) REFERENCES zones(zone_id)
      ON UPDATE CASCADE
      ON DELETE SET NULL
);

-- optional index for performance
CREATE INDEX idx_households_zone ON households(zone_id);

CREATE TABLE users (
  user_id BIGINT NOT NULL IDENTITY(1,1),
  household_id BIGINT NULL,
  name NVARCHAR(120) NOT NULL,
  email NVARCHAR(190) UNIQUE,
  phone NVARCHAR(40),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_users PRIMARY KEY (user_id),
  CONSTRAINT fk_users_household
      FOREIGN KEY (household_id) REFERENCES households(household_id)
      ON UPDATE CASCADE
      ON DELETE SET NULL
);
-- =========================
-- 3) Item catalog & instances
-- =========================
CREATE TABLE items (
  item_id BIGINT NOT NULL IDENTITY(1,1),
  sku NVARCHAR(64) UNIQUE,
  name NVARCHAR(160) NOT NULL,
  category NVARCHAR(80),
  typical_shelf_life_days INT,
  unit NVARCHAR(24),  -- e.g. 'kg', 'pcs', 'L'
  CONSTRAINT pk_items PRIMARY KEY (item_id)
);

CREATE TABLE dbo.item_instances (
  instance_id BIGINT NOT NULL IDENTITY(1,1),
  item_id BIGINT NOT NULL,
  household_id BIGINT NOT NULL,
  quantity DECIMAL(10,2) NOT NULL CONSTRAINT df_item_instances_qty DEFAULT(1.00),
  batch_code NVARCHAR(80) NULL,
  purchased_at DATE NULL,
  estimated_expiry DATE NULL,
  storage_instructions NVARCHAR(255) NULL,
  state NVARCHAR(12) NOT NULL CONSTRAINT df_item_instances_state DEFAULT N'available',
  created_at DATETIME2 NOT NULL CONSTRAINT df_item_instances_created DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_item_instances PRIMARY KEY (instance_id),
  CONSTRAINT fk_item_instances_item
      FOREIGN KEY (item_id) REFERENCES dbo.items(item_id)
      ON UPDATE CASCADE ON DELETE NO ACTION,     -- MySQL RESTRICT ≈ NO ACTION
  CONSTRAINT fk_item_instances_household
      FOREIGN KEY (household_id) REFERENCES dbo.households(household_id)
      ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_item_instances_state
      CHECK (state IN (N'available',N'offered',N'reserved',N'exchanged',N'wasted'))
);

-- =========================
-- 4) Offers & Requests
-- =========================
IF OBJECT_ID('dbo.offers','U') IS NOT NULL DROP TABLE dbo.offers;
GO
CREATE TABLE dbo.offers (
  offer_id BIGINT NOT NULL IDENTITY(1,1),
  instance_id BIGINT NOT NULL,
  offered_by BIGINT NULL,              -- make nullable to allow SET NULL
  description NVARCHAR(255) NULL,
  valid_until DATETIME2 NULL,
  status NVARCHAR(10) NOT NULL CONSTRAINT df_offers_status DEFAULT N'open',
  created_at DATETIME2 NOT NULL CONSTRAINT df_offers_created DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_offers PRIMARY KEY (offer_id),
  CONSTRAINT fk_offers_instance
    FOREIGN KEY (instance_id) REFERENCES dbo.item_instances(instance_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_offers_user
    FOREIGN KEY (offered_by) REFERENCES dbo.users(user_id)
    ON UPDATE NO ACTION ON DELETE SET NULL,

  CONSTRAINT ck_offers_status CHECK (status IN (N'open',N'matched',N'closed'))
);

CREATE TABLE dbo.requests (
  request_id BIGINT NOT NULL IDENTITY(1,1),
  requested_by BIGINT NOT NULL,     -- users.user_id
  item_id BIGINT NOT NULL,
  desired_quantity DECIMAL(10,2) NOT NULL CONSTRAINT df_requests_qty DEFAULT(1.00),
  max_distance_m INT NULL CONSTRAINT df_requests_maxdist DEFAULT(1000),
  status NVARCHAR(10) NOT NULL CONSTRAINT df_requests_status DEFAULT N'open',
  created_at DATETIME2 NOT NULL CONSTRAINT df_requests_created DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_requests PRIMARY KEY (request_id),
  CONSTRAINT fk_requests_item
      FOREIGN KEY (item_id) REFERENCES dbo.items(item_id)
      ON UPDATE CASCADE ON DELETE NO ACTION,     -- MySQL RESTRICT ≈ NO ACTION
  CONSTRAINT fk_requests_user
      FOREIGN KEY (requested_by) REFERENCES dbo.users(user_id)
      ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_requests_status
      CHECK (status IN (N'open',N'matched',N'closed'))
);

-- =========================
-- 5) Exchanges (matches)
-- =========================
CREATE TABLE dbo.exchanges (
  exchange_id       BIGINT NOT NULL IDENTITY(1,1),
  offer_id          BIGINT NOT NULL,
  request_id        BIGINT NULL,
  giver_user_id     BIGINT NULL,
  receiver_user_id  BIGINT NULL,
  exchange_time     DATETIME2 NOT NULL CONSTRAINT df_exchanges_time DEFAULT SYSUTCDATETIME(),
  status            NVARCHAR(10) NOT NULL CONSTRAINT df_exchanges_status DEFAULT N'completed',
  CONSTRAINT pk_exchanges PRIMARY KEY (exchange_id),
  CONSTRAINT fk_exchanges_offer
    FOREIGN KEY (offer_id) REFERENCES dbo.offers(offer_id)
    ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_exchanges_request
    FOREIGN KEY (request_id) REFERENCES dbo.requests(request_id)
    ON UPDATE NO ACTION ON DELETE NO ACTION,
  CONSTRAINT fk_exchanges_giver
    FOREIGN KEY (giver_user_id) REFERENCES dbo.users(user_id)
    ON UPDATE NO ACTION ON DELETE NO ACTION,
  CONSTRAINT fk_exchanges_receiver
    FOREIGN KEY (receiver_user_id) REFERENCES dbo.users(user_id)
    ON UPDATE NO ACTION ON DELETE NO ACTION,
  CONSTRAINT ck_exchanges_status CHECK (status IN (N'pending',N'completed',N'cancelled'))
);

-- =========================
-- 6) Incentive tokens (ledger)
-- =========================
CREATE TABLE dbo.token_transactions (
  tx_id      BIGINT NOT NULL IDENTITY(1,1),
  user_id    BIGINT NOT NULL,
  delta      INT NOT NULL,   -- positive or negative
  reason     NVARCHAR(255) NULL,
  created_at DATETIME2 NOT NULL CONSTRAINT df_tokens_created DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_token_transactions PRIMARY KEY (tx_id),
  CONSTRAINT fk_tokens_user
      FOREIGN KEY (user_id) REFERENCES dbo.users(user_id)
      ON UPDATE CASCADE ON DELETE CASCADE
);

-- =========================
-- 7) Sensors (spoilage risk)
-- =========================

CREATE TABLE dbo.sensor_readings (
  reading_id     BIGINT NOT NULL IDENTITY(1,1),
  household_id   BIGINT NULL,
  instance_id    BIGINT NULL,
  sensor_type    NVARCHAR(20) NOT NULL,   -- enum-like via CHECK below
  reading_value  DECIMAL(10,3) NOT NULL,
  measured_at    DATETIME2 NOT NULL CONSTRAINT df_sensor_measured DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_sensor_readings PRIMARY KEY (reading_id),
  CONSTRAINT fk_sensor_household
      FOREIGN KEY (household_id) REFERENCES dbo.households(household_id)
      ON UPDATE NO ACTION ON DELETE SET NULL,
  CONSTRAINT fk_sensor_instance
      FOREIGN KEY (instance_id) REFERENCES dbo.item_instances(instance_id)
      ON UPDATE NO ACTION ON DELETE NO ACTION,

  CONSTRAINT ck_sensor_type
      CHECK (sensor_type IN (N'temperature',N'humidity',N'co2',N'door_open'))
);

-- =========================
-- 8) Audit logs
-- =========================
CREATE TABLE dbo.audit_logs (
  log_id        BIGINT NOT NULL IDENTITY(1,1),
  instance_id   BIGINT NULL,
  event_type    NVARCHAR(64) NOT NULL,         
  event_detail  NVARCHAR(MAX) NULL,  
  created_at    DATETIME2 NOT NULL CONSTRAINT df_audit_created DEFAULT SYSUTCDATETIME(),
  CONSTRAINT pk_audit_logs PRIMARY KEY (log_id),
  CONSTRAINT fk_audit_instance
      FOREIGN KEY (instance_id) REFERENCES dbo.item_instances(instance_id)
      ON UPDATE CASCADE ON DELETE SET NULL,

);



-- INSERTS FOR dbo.zones (30 rows)
SET IDENTITY_INSERT dbo.zones ON;
INSERT INTO dbo.zones (zone_id, name, center_lat, center_lng) VALUES
(1, N'Zone 1', 41.407408, 2.059403),
(2, N'Zone 2', 41.349105, 2.106971),
(3, N'Zone 3', 41.422935, 2.215808),
(4, N'Zone 4', 41.447849, 2.074265),
(5, N'Zone 5', 41.372607, 2.060551),
(6, N'Zone 6', 41.340082, 2.174685),
(7, N'Zone 7', 41.309346, 2.101121),
(8, N'Zone 8', 41.409082, 2.184186),
(9, N'Zone 9', 41.34037, 2.194824),
(10, N'Zone 10', 41.434609, 2.05496),
(11, N'Zone 11', 41.434031, 2.220953),
(12, N'Zone 12', 41.35954, 2.090715),
(13, N'Zone 13', 41.458254, 2.134183),
(14, N'Zone 14', 41.319939, 2.076612),
(15, N'Zone 15', 41.440699, 2.198294),
(16, N'Zone 16', 41.434241, 2.228536),
(17, N'Zone 17', 41.390896, 2.286948),
(18, N'Zone 18', 41.365666, 2.18589),
(19, N'Zone 19', 41.437805, 2.201845),
(20, N'Zone 20', 41.442973, 2.191965),
(21, N'Zone 21', 41.417831, 2.064398),
(22, N'Zone 22', 41.341564, 2.122853),
(23, N'Zone 23', 41.317867, 2.10927),
(24, N'Zone 24', 41.32126, 2.120114),
(25, N'Zone 25', 41.40681, 2.14096),
(26, N'Zone 26', 41.364329, 2.103682),
(27, N'Zone 27', 41.347816, 2.278197),
(28, N'Zone 28', 41.408786, 2.199591),
(29, N'Zone 29', 41.332482, 2.22839),
(30, N'Zone 30', 41.331244, 2.144469);
SET IDENTITY_INSERT dbo.zones OFF;

-- INSERTS FOR dbo.households (30 rows)
SET IDENTITY_INSERT dbo.households ON;
INSERT INTO dbo.households (household_id, address, geo_lat, geo_lng, zone_id, created_at) VALUES
(1, N'Carrer de Balmes 57, Barcelona', 41.414638, 2.255684, 1, '2025-06-21 14:52:58'),
(2, N'Gran Via 59, Barcelona', 41.436588, 2.246611, 2, '2025-08-08 14:52:58'),
(3, N'Carrer de Valencia 17, Barcelona', 41.338857, 2.279698, 3, '2025-06-29 14:52:58'),
(4, N'Carrer de Arago 55, Barcelona', 41.40997, 2.148352, 4, '2025-07-08 14:52:58'),
(5, N'Carrer de Sants 37, Barcelona', 41.347481, 2.112591, 5, '2025-07-19 14:52:58'),
(6, N'Carrer de Balmes 68, Barcelona', 41.424622, 2.156224, 6, '2025-07-16 14:52:58'),
(7, N'Ronda Sant Pere 93, Barcelona', 41.340191, 2.292809, 7, '2025-07-25 14:52:58'),
(8, N'Carrer de Sants 24, Barcelona', 41.426025, 2.260065, 8, '2025-09-09 14:52:58'),
(9, N'Passeig de Gracia 203, Barcelona', 41.413977, 2.196538, 9, '2025-08-10 14:52:58'),
(10, N'Ronda Sant Pere 153, Barcelona', 41.464479, 2.180387, 10, '2025-07-20 14:52:58'),
(11, N'Gran Via 175, Barcelona', 41.420415, 2.21701, 1, '2025-07-22 14:52:58'),
(12, N'Carrer de Valencia 197, Barcelona', 41.407654, 2.080173, 2, '2025-08-04 14:52:58'),
(13, N'Passeig de Gracia 117, Barcelona', 41.305619, 2.226702, 3, '2025-06-28 14:52:58'),
(14, N'Carrer de Valencia 249, Barcelona', 41.385194, 2.096276, 4, '2025-09-15 14:52:58'),
(15, N'Carrer de Valencia 216, Barcelona', 41.407332, 2.199553, 5, '2025-09-09 14:52:58'),
(16, N'Carrer de Arago 196, Barcelona', 41.330948, 2.28224, 6, '2025-07-23 14:52:58'),
(17, N'Gran Via 154, Barcelona', 41.356965, 2.058074, 7, '2025-08-13 14:52:58'),
(18, N'Carrer de Valencia 62, Barcelona', 41.314368, 2.264122, 8, '2025-09-18 14:52:58'),
(19, N'Diagonal Ave 188, Barcelona', 41.382858, 2.070011, 9, '2025-06-23 14:52:58'),
(20, N'Carrer de Balmes 197, Barcelona', 41.325222, 2.21174, 10, '2025-07-20 14:52:58'),
(21, N'Passeig de Gracia 68, Barcelona', 41.389528, 2.198983, 1, '2025-09-01 14:52:58'),
(22, N'Carrer de Balmes 194, Barcelona', 41.421889, 2.101676, 2, '2025-08-20 14:52:58'),
(23, N'Ronda Sant Pere 172, Barcelona', 41.40908, 2.158544, 3, '2025-07-24 14:52:58'),
(24, N'Carrer de Sants 31, Barcelona', 41.344765, 2.068766, 4, '2025-09-26 14:52:58'),
(25, N'Carrer de Marina 142, Barcelona', 41.341918, 2.106252, 5, '2025-09-19 14:52:58'),
(26, N'Gran Via 59, Barcelona', 41.315884, 2.060939, 6, '2025-08-17 14:52:58'),
(27, N'Diagonal Ave 132, Barcelona', 41.343181, 2.213955, 7, '2025-09-01 14:52:58'),
(28, N'Carrer de Balmes 34, Barcelona', 41.420836, 2.265172, 8, '2025-07-17 14:52:58'),
(29, N'Carrer de Sants 63, Barcelona', 41.430639, 2.247199, 9, '2025-09-04 14:52:58'),
(30, N'Diagonal Ave 25, Barcelona', 41.410537, 2.138431, 10, '2025-08-07 14:52:58');
SET IDENTITY_INSERT dbo.households OFF;

-- INSERTS FOR dbo.users (30 rows)
SET IDENTITY_INSERT dbo.users ON;
INSERT INTO dbo.users (user_id, household_id, name, email, phone, created_at) VALUES
(1, 1, N'Aisha Ahmed', N'aisha.ahmed1@demo.net', N'+34 6931908841', '2025-07-12 14:52:58'),
(2, 2, N'Bilal Khan', N'bilal.khan2@yahoo.com', N'+34 6122016911', '2025-08-13 14:52:58'),
(3, 3, N'Carlos Hernandez', N'carlos.hernandez3@yahoo.com', N'+34 6432833230', '2025-09-02 14:52:58'),
(4, 4, N'Diana Lopez', N'diana.lopez4@outlook.com', N'+34 6249997381', '2025-08-07 14:52:58'),
(5, 5, N'Elena Garcia', N'elena.garcia5@outlook.com', N'+34 6544078418', '2025-08-29 14:52:58'),
(6, 6, N'Farhan Iqbal', N'farhan.iqbal6@demo.net', N'+34 6312264748', '2025-08-08 14:52:58'),
(7, 7, N'Gabriela Rodriguez', N'gabriela.rodriguez7@gmail.com', N'+34 6121848731', '2025-07-12 14:52:58'),
(8, 8, N'Hassan Hussain', N'hassan.hussain8@gmail.com', N'+34 6012564689', '2025-09-03 14:52:58'),
(9, 9, N'Imran Raza', N'imran.raza9@outlook.com', N'+34 6529147706', '2025-08-03 14:52:58'),
(10, 10, N'Julia Martinez', N'julia.martinez10@outlook.com', N'+34 6511983738', '2025-09-12 14:52:58'),
(11, 11, N'Kamal Saeed', N'kamal.saeed11@demo.net', N'+34 6007550190', '2025-08-31 14:52:58'),
(12, 12, N'Lina Fernandez', N'lina.fernandez12@demo.net', N'+34 6368096887', '2025-07-24 14:52:58'),
(13, 13, N'Mateo Ruiz', N'mateo.ruiz13@yahoo.com', N'+34 6919164991', '2025-09-14 14:52:58'),
(14, 14, N'Nadia Sanchez', N'nadia.sanchez14@outlook.com', N'+34 6374652414', '2025-09-26 14:52:58'),
(15, 15, N'Omar Ali', N'omar.ali15@gmail.com', N'+34 6942022698', '2025-08-24 14:52:58'),
(16, 16, N'Paula Ortega', N'paula.ortega16@mail.com', N'+34 6068999183', '2025-07-31 14:52:58'),
(17, 17, N'Qasim Qureshi', N'qasim.qureshi17@gmail.com', N'+34 6201954280', '2025-07-30 14:52:58'),
(18, 18, N'Rania Ramos', N'rania.ramos18@mail.com', N'+34 6232149597', '2025-07-19 14:52:58'),
(19, 19, N'Sami Soto', N'sami.soto19@mail.com', N'+34 6864946066', '2025-08-13 14:52:58'),
(20, 20, N'Tania Tariq', N'tania.tariq20@mail.com', N'+34 6725130808', '2025-07-21 14:52:58'),
(21, 21, N'Usman Uddin', N'usman.uddin21@gmail.com', N'+34 6052375453', '2025-08-11 14:52:58'),
(22, 22, N'Valeria Vega', N'valeria.vega22@yahoo.com', N'+34 6749770838', '2025-08-24 14:52:58'),
(23, 23, N'Waqas Waris', N'waqas.waris23@example.org', N'+34 6266271130', '2025-09-03 14:52:58'),
(24, 24, N'Ximena Xavier', N'ximena.xavier24@example.org', N'+34 6503195773', '2025-07-10 14:52:58'),
(25, 25, N'Yasir Yunus', N'yasir.yunus25@yahoo.com', N'+34 6388670955', '2025-08-24 14:52:58'),
(26, 26, N'Zara Zahid', N'zara.zahid26@mail.com', N'+34 6018688755', '2025-07-16 14:52:58'),
(27, 27, N'Noor Nawaz', N'noor.nawaz27@gmail.com', N'+34 6122229110', '2025-07-27 14:52:58'),
(28, 28, N'Alejandro Alonso', N'alejandro.alonso28@outlook.com', N'+34 6645449324', '2025-09-17 14:52:58'),
(29, 29, N'Beatriz Barrios', N'beatriz.barrios29@example.org', N'+34 6085098412', '2025-08-17 14:52:58'),
(30, 30, N'Hiba Hanan', N'hiba.hanan30@example.org', N'+34 6208351517', '2025-07-26 14:52:58');
SET IDENTITY_INSERT dbo.users OFF;

-- INSERTS FOR dbo.items (30 rows)
SET IDENTITY_INSERT dbo.items ON;
INSERT INTO dbo.items (item_id, sku, name, category, typical_shelf_life_days, unit) VALUES
(1, N'SKU-1001', N'Milk, semi-skimmed 1L', N'Dairy', 7, N'L'),
(2, N'SKU-1002', N'Eggs, free-range 12pcs', N'Dairy', 14, N'pcs'),
(3, N'SKU-1003', N'Chicken breast 500g', N'Meat', 3, N'kg'),
(4, N'SKU-1004', N'Tomatoes 1kg', N'Produce', 5, N'kg'),
(5, N'SKU-1005', N'Bananas 1kg', N'Produce', 5, N'kg'),
(6, N'SKU-1006', N'Rice Basmati 5kg', N'Grains', 365, N'kg'),
(7, N'SKU-1007', N'Lentils 1kg', N'Grains', 365, N'kg'),
(8, N'SKU-1008', N'Olive oil 1L', N'Pantry', 720, N'L'),
(9, N'SKU-1009', N'Sugar 1kg', N'Pantry', 720, N'kg'),
(10, N'SKU-1010', N'Flour 1kg', N'Pantry', 180, N'kg'),
(11, N'SKU-1011', N'Yogurt 500g', N'Dairy', 10, N'kg'),
(12, N'SKU-1012', N'Cheddar cheese 200g', N'Dairy', 30, N'kg'),
(13, N'SKU-1013', N'Butter 250g', N'Dairy', 90, N'kg'),
(14, N'SKU-1014', N'Spinach 300g', N'Produce', 4, N'kg'),
(15, N'SKU-1015', N'Apples 1kg', N'Produce', 21, N'kg'),
(16, N'SKU-1016', N'Oranges 1kg', N'Produce', 14, N'kg'),
(17, N'SKU-1017', N'Pasta 500g', N'Grains', 720, N'kg'),
(18, N'SKU-1018', N'Tuna canned 160g', N'Pantry', 720, N'kg'),
(19, N'SKU-1019', N'Chickpeas 1kg', N'Grains', 365, N'kg'),
(20, N'SKU-1020', N'Salt 1kg', N'Pantry', 3650, N'kg'),
(21, N'SKU-1021', N'Black pepper 100g', N'Pantry', 3650, N'kg'),
(22, N'SKU-1022', N'Tea 200g', N'Pantry', 3650, N'kg'),
(23, N'SKU-1023', N'Coffee 250g', N'Pantry', 3650, N'kg'),
(24, N'SKU-1024', N'Frozen peas 1kg', N'Frozen', 365, N'kg'),
(25, N'SKU-1025', N'Frozen paratha 400g', N'Frozen', 365, N'kg'),
(26, N'SKU-1026', N'Bread loaf 400g', N'Bakery', 3, N'kg'),
(27, N'SKU-1027', N'Baguette 250g', N'Bakery', 2, N'kg'),
(28, N'SKU-1028', N'Tomato sauce 500ml', N'Pantry', 365, N'L'),
(29, N'SKU-1029', N'Cornflakes 375g', N'Pantry', 365, N'kg'),
(30, N'SKU-1030', N'Honey 500g', N'Pantry', 720, N'kg');
SET IDENTITY_INSERT dbo.items OFF;

-- INSERTS FOR dbo.item_instances (30 rows)
SET IDENTITY_INSERT dbo.item_instances ON;
INSERT INTO dbo.item_instances
(instance_id, item_id, household_id, quantity, batch_code, purchased_at, estimated_expiry, storage_instructions, state, created_at) VALUES
(1, 1, 1, 3.58, N'BAT-90173', '2025-09-12', '2025-10-25', N'Keep refrigerated', N'wasted', '2025-09-27 16:14:58'),
(2, 2, 2, 0.7, N'BAT-27601', '2025-09-29', '2025-10-12', N'Keep refrigerated', N'wasted', '2025-10-03 05:35:58'),
(3, 3, 3, 1.55, N'BAT-37607', '2025-09-15', '2025-10-19', N'Room temperature', N'reserved', '2025-09-20 22:12:58'),
(4, 4, 4, 1.41, N'BAT-16658', '2025-10-05', '2025-10-22', N'Freeze if not used in 2 days', N'available', '2025-10-07 03:29:58'),
(5, 5, 5, 3.9, N'BAT-93507', '2025-09-29', '2025-10-14', N'Store in airtight container', N'wasted', '2025-09-23 19:44:58'),
(6, 6, 6, 0.25, N'BAT-19862', '2025-09-09', '2025-10-13', N'Keep refrigerated', N'reserved', '2025-09-18 20:01:58'),
(7, 7, 7, 0.91, N'BAT-26704', '2025-10-06', '2025-10-18', N'Freeze if not used in 2 days', N'available', '2025-09-26 07:42:58'),
(8, 8, 8, 3.47, N'BAT-97416', '2025-10-04', '2025-10-20', N'Store in airtight container', N'wasted', '2025-10-03 06:48:58'),
(9, 9, 9, 4.35, N'BAT-33206', '2025-09-09', '2025-10-22', N'Keep refrigerated', N'offered', '2025-09-27 00:49:58'),
(10, 10, 10, 4.05, N'BAT-42527', '2025-09-29', '2025-10-14', N'Keep refrigerated', N'exchanged', '2025-10-05 22:49:58'),
(11, 11, 11, 1.27, N'BAT-70332', '2025-09-26', '2025-10-18', N'Room temperature', N'offered', '2025-10-06 16:21:58'),
(12, 12, 12, 1.13, N'BAT-53025', '2025-09-29', '2025-10-11', N'Freeze if not used in 2 days', N'reserved', '2025-09-21 01:14:58'),
(13, 13, 13, 3.46, N'BAT-80282', '2025-09-27', '2025-10-09', N'Keep refrigerated', N'reserved', '2025-10-01 19:03:58'),
(14, 14, 14, 4.82, N'BAT-44795', '2025-10-06', '2025-10-12', N'Store in airtight container', N'reserved', '2025-09-26 23:59:58'),
(15, 15, 15, 3.11, N'BAT-77033', '2025-10-04', '2025-10-21', N'Room temperature', N'reserved', '2025-10-05 23:59:58'),
(16, 16, 16, 0.21, N'BAT-80575', '2025-09-16', '2025-10-15', N'Freeze if not used in 2 days', N'exchanged', '2025-10-04 16:12:58'),
(17, 17, 17, 4.62, N'BAT-91678', '2025-09-27', '2025-10-12', N'Freeze if not used in 2 days', N'wasted', '2025-09-27 16:07:58'),
(18, 18, 18, 2.16, N'BAT-62743', '2025-09-15', '2025-10-18', N'Room temperature', N'offered', '2025-09-23 16:11:58'),
(19, 19, 19, 4.71, N'BAT-98777', '2025-09-14', '2025-10-14', N'Freeze if not used in 2 days', N'exchanged', '2025-09-20 14:52:58'),
(20, 20, 20, 1.66, N'BAT-37549', '2025-09-24', '2025-10-27', N'Freeze if not used in 2 days', N'exchanged', '2025-09-22 23:47:58'),
(21, 21, 21, 3.44, N'BAT-77000', '2025-09-22', '2025-10-14', N'Keep refrigerated', N'reserved', '2025-09-20 16:13:58'),
(22, 22, 22, 3.24, N'BAT-53933', '2025-10-05', '2025-10-16', N'Freeze if not used in 2 days', N'offered', '2025-10-01 09:51:58'),
(23, 23, 23, 0.32, N'BAT-42092', '2025-09-22', '2025-10-28', N'Keep refrigerated', N'exchanged', '2025-09-23 17:23:58'),
(24, 24, 24, 2.96, N'BAT-60328', '2025-09-22', '2025-10-21', N'Room temperature', N'offered', '2025-10-07 11:14:58'),
(25, 25, 25, 3.94, N'BAT-38683', '2025-10-02', '2025-10-25', N'Store in airtight container', N'available', '2025-09-20 06:22:58'),
(26, 26, 26, 4.6, N'BAT-25906', '2025-09-23', '2025-10-13', N'Store in airtight container', N'wasted', '2025-09-19 18:33:58'),
(27, 27, 27, 1.72, N'BAT-68008', '2025-09-18', '2025-10-25', N'Store in airtight container', N'wasted', '2025-09-23 09:27:58'),
(28, 28, 28, 3.77, N'BAT-72216', '2025-09-23', '2025-10-17', N'Room temperature', N'reserved', '2025-09-20 22:20:58'),
(29, 29, 29, 3.21, N'BAT-45992', '2025-09-23', '2025-10-11', N'Freeze if not used in 2 days', N'offered', '2025-09-29 03:25:58'),
(30, 30, 30, 1.73, N'BAT-80798', '2025-10-05', '2025-10-13', N'Room temperature', N'offered', '2025-09-24 15:11:58');
SET IDENTITY_INSERT dbo.item_instances OFF;

-- INSERTS FOR dbo.offers (30 rows)
SET IDENTITY_INSERT dbo.offers ON;
INSERT INTO dbo.offers
(offer_id, instance_id, offered_by, description, valid_until, status, created_at) VALUES
(1, 1, 1, N'Pickup this evening', '2025-10-14 14:52:58', N'open', '2025-10-08 14:52:58'),
(2, 2, 2, N'Prefer quick pickup', '2025-10-12 14:52:58', N'matched', '2025-10-04 14:52:58'),
(3, 3, 3, N'Prefer quick pickup', '2025-10-12 14:52:58', N'open', '2025-10-07 14:52:58'),
(4, 4, 4, N'Prefer quick pickup', '2025-10-12 14:52:58', N'closed', '2025-10-03 14:52:58'),
(5, 5, 5, N'Free to a good home', '2025-10-15 14:52:58', N'closed', '2025-10-05 14:52:58'),
(6, 6, 6, N'Prefer quick pickup', '2025-10-09 14:52:58', N'matched', '2025-10-06 14:52:58'),
(7, 7, 7, N'Prefer quick pickup', '2025-10-15 14:52:58', N'matched', '2025-10-04 14:52:58'),
(8, 8, 8, N'Brand new/unopened', '2025-10-15 14:52:58', N'closed', '2025-10-07 14:52:58'),
(9, 9, 9, N'Prefer quick pickup', '2025-10-10 14:52:58', N'matched', '2025-10-05 14:52:58'),
(10, 10, 10, N'Prefer quick pickup', '2025-10-09 14:52:58', N'matched', '2025-10-06 14:52:58'),
(11, 11, 11, N'Prefer quick pickup', '2025-10-14 14:52:58', N'open', '2025-10-05 14:52:58'),
(12, 12, 12, N'Pickup this evening', '2025-10-13 14:52:58', N'closed', '2025-10-08 14:52:58'),
(13, 13, 13, N'Prefer quick pickup', '2025-10-13 14:52:58', N'closed', '2025-10-03 14:52:58'),
(14, 14, 14, N'Free to a good home', '2025-10-09 14:52:58', N'closed', '2025-10-05 14:52:58'),
(15, 15, 15, N'Pickup this evening', '2025-10-15 14:52:58', N'matched', '2025-10-07 14:52:58'),
(16, 16, 16, N'Free to a good home', '2025-10-11 14:52:58', N'matched', '2025-10-06 14:52:58'),
(17, 17, 17, N'Pickup this evening', '2025-10-12 14:52:58', N'matched', '2025-10-06 14:52:58'),
(18, 18, 18, N'Prefer quick pickup', '2025-10-11 14:52:58', N'matched', '2025-10-06 14:52:58'),
(19, 19, 19, N'Free to a good home', '2025-10-12 14:52:58', N'open', '2025-10-03 14:52:58'),
(20, 20, 20, N'Brand new/unopened', '2025-10-09 14:52:58', N'matched', '2025-10-07 14:52:58'),
(21, 21, 21, N'Free to a good home', '2025-10-15 14:52:58', N'closed', '2025-10-08 14:52:58'),
(22, 22, 22, N'Free to a good home', '2025-10-10 14:52:58', N'open', '2025-10-08 14:52:58'),
(23, 23, 23, N'Brand new/unopened', '2025-10-10 14:52:58', N'open', '2025-10-07 14:52:58'),
(24, 24, 24, N'Prefer quick pickup', '2025-10-14 14:52:58', N'open', '2025-10-04 14:52:58'),
(25, 25, 25, N'Pickup this evening', '2025-10-12 14:52:58', N'closed', '2025-10-06 14:52:58'),
(26, 26, 26, N'Near metro station', '2025-10-10 14:52:58', N'closed', '2025-10-04 14:52:58'),
(27, 27, 27, N'Free to a good home', '2025-10-15 14:52:58', N'open', '2025-10-06 14:52:58'),
(28, 28, 28, N'Free to a good home', '2025-10-13 14:52:58', N'open', '2025-10-06 14:52:58'),
(29, 29, 29, N'Brand new/unopened', '2025-10-14 14:52:58', N'matched', '2025-10-05 14:52:58'),
(30, 30, 30, N'Pickup this evening', '2025-10-09 14:52:58', N'closed', '2025-10-03 14:52:58');
SET IDENTITY_INSERT dbo.offers OFF;

-- INSERTS FOR dbo.requests (30 rows)
SET IDENTITY_INSERT dbo.requests ON;
INSERT INTO dbo.requests
(request_id, requested_by, item_id, desired_quantity, max_distance_m, status, created_at) VALUES
(1, 6, 4, 2.58, 800, N'open', '2025-10-03 14:52:58'),
(2, 7, 5, 2.43, 2000, N'open', '2025-10-04 14:52:58'),
(3, 8, 6, 2.46, 1000, N'closed', '2025-10-05 14:52:58'),
(4, 9, 7, 2.15, 500, N'closed', '2025-10-03 14:52:58'),
(5, 10, 8, 1.35, 1500, N'matched', '2025-10-08 14:52:58'),
(6, 11, 9, 1.58, 1000, N'closed', '2025-10-05 14:52:58'),
(7, 12, 10, 2.27, 1500, N'open', '2025-10-03 14:52:58'),
(8, 13, 11, 1.8, 1000, N'closed', '2025-10-04 14:52:58'),
(9, 14, 12, 2.44, 1500, N'matched', '2025-10-03 14:52:58'),
(10, 15, 13, 1.98, 1000, N'open', '2025-10-08 14:52:58'),
(11, 16, 14, 1.2, 1500, N'open', '2025-10-05 14:52:58'),
(12, 17, 15, 1.92, 1500, N'matched', '2025-10-08 14:52:58'),
(13, 18, 16, 1.74, 1000, N'open', '2025-10-05 14:52:58'),
(14, 19, 17, 1.03, 1000, N'matched', '2025-10-06 14:52:58'),
(15, 20, 18, 2.7, 1000, N'closed', '2025-10-08 14:52:58'),
(16, 21, 19, 1.79, 800, N'open', '2025-10-07 14:52:58'),
(17, 22, 20, 2.3, 1500, N'closed', '2025-10-07 14:52:58'),
(18, 23, 21, 2.23, 1500, N'matched', '2025-10-08 14:52:58'),
(19, 24, 22, 0.73, 800, N'matched', '2025-10-03 14:52:58'),
(20, 25, 23, 1.11, 2000, N'matched', '2025-10-05 14:52:58'),
(21, 26, 24, 1.88, 1000, N'matched', '2025-10-03 14:52:58'),
(22, 27, 25, 1.88, 1000, N'closed', '2025-10-05 14:52:58'),
(23, 28, 26, 1.18, 1000, N'open', '2025-10-08 14:52:58'),
(24, 29, 27, 2.3, 1000, N'open', '2025-10-03 14:52:58'),
(25, 30, 28, 1.84, 800, N'open', '2025-10-07 14:52:58'),
(26, 1, 29, 2.35, 1000, N'closed', '2025-10-04 14:52:58'),
(27, 2, 30, 2.94, 2000, N'closed', '2025-10-06 14:52:58'),
(28, 3, 1, 2.95, 800, N'matched', '2025-10-07 14:52:58'),
(29, 4, 2, 1.4, 1000, N'open', '2025-10-03 14:52:58'),
(30, 5, 3, 1.84, 1000, N'open', '2025-10-08 14:52:58');
SET IDENTITY_INSERT dbo.requests OFF;

-- INSERTS FOR dbo.exchanges (30 rows)
SET IDENTITY_INSERT dbo.exchanges ON;
INSERT INTO dbo.exchanges
(exchange_id, offer_id, request_id, giver_user_id, receiver_user_id, exchange_time, status) VALUES
(1, 1, 1, 1, 8, '2025-10-06 14:52:58', N'cancelled'),
(2, 2, 2, 2, 9, '2025-10-07 14:52:58', N'cancelled'),
(3, 3, 3, 3, 10, '2025-10-05 14:52:58', N'pending'),
(4, 4, 4, 4, 11, '2025-10-08 14:52:58', N'cancelled'),
(5, 5, 5, 5, 12, '2025-10-06 14:52:58', N'completed'),
(6, 6, 6, 6, 13, '2025-10-05 14:52:58', N'completed'),
(7, 7, 7, 7, 14, '2025-10-06 14:52:58', N'pending'),
(8, 8, 8, 8, 15, '2025-10-08 14:52:58', N'completed'),
(9, 9, 9, 9, 16, '2025-10-05 14:52:58', N'pending'),
(10, 10, 10, 10, 17, '2025-10-08 14:52:58', N'completed'),
(11, 11, 11, 11, 18, '2025-10-05 14:52:58', N'pending'),
(12, 12, 12, 12, 19, '2025-10-08 14:52:58', N'pending'),
(13, 13, 13, 13, 20, '2025-10-07 14:52:58', N'cancelled'),
(14, 14, 14, 14, 21, '2025-10-06 14:52:58', N'pending'),
(15, 15, 15, 15, 22, '2025-10-07 14:52:58', N'pending'),
(16, 16, 16, 16, 23, '2025-10-05 14:52:58', N'cancelled'),
(17, 17, 17, 17, 24, '2025-10-07 14:52:58', N'cancelled'),
(18, 18, 18, 18, 25, '2025-10-05 14:52:58', N'completed'),
(19, 19, 19, 19, 26, '2025-10-05 14:52:58', N'completed'),
(20, 20, 20, 20, 27, '2025-10-05 14:52:58', N'completed'),
(21, 21, 21, 21, 28, '2025-10-08 14:52:58', N'cancelled'),
(22, 22, 22, 22, 29, '2025-10-08 14:52:58', N'pending'),
(23, 23, 23, 23, 30, '2025-10-07 14:52:58', N'completed'),
(24, 24, 24, 24, 1, '2025-10-08 14:52:58', N'pending'),
(25, 25, 25, 25, 2, '2025-10-07 14:52:58', N'pending'),
(26, 26, 26, 26, 3, '2025-10-08 14:52:58', N'pending'),
(27, 27, 27, 27, 4, '2025-10-08 14:52:58', N'completed'),
(28, 28, 28, 28, 5, '2025-10-05 14:52:58', N'cancelled'),
(29, 29, 29, 29, 6, '2025-10-05 14:52:58', N'completed'),
(30, 30, 30, 30, 7, '2025-10-08 14:52:58', N'pending');
SET IDENTITY_INSERT dbo.exchanges OFF;

-- INSERTS FOR dbo.token_transactions (30 rows)
SET IDENTITY_INSERT dbo.token_transactions ON;
INSERT INTO dbo.token_transactions
(tx_id, user_id, delta, reason, created_at) VALUES
(1, 1, 15, N'Admin adjustment', '2025-10-01 14:52:58'),
(2, 2, 5, N'Request fulfilled', '2025-10-04 14:52:58'),
(3, 3, -10, N'Bonus: reducing waste', '2025-09-28 14:52:58'),
(4, 4, 10, N'Penalty: no-show', '2025-10-07 14:52:58'),
(5, 5, 20, N'Request fulfilled', '2025-09-28 14:52:58'),
(6, 6, 10, N'Admin adjustment', '2025-10-06 14:52:58'),
(7, 7, 5, N'Offer completed', '2025-10-06 14:52:58'),
(8, 8, 15, N'Bonus: reducing waste', '2025-09-29 14:52:58'),
(9, 9, 15, N'Penalty: no-show', '2025-10-07 14:52:58'),
(10, 10, -5, N'Admin adjustment', '2025-10-02 14:52:58'),
(11, 11, 15, N'Bonus: reducing waste', '2025-09-30 14:52:58'),
(12, 12, -5, N'Penalty: no-show', '2025-10-07 14:52:58'),
(13, 13, 20, N'Offer completed', '2025-10-02 14:52:58'),
(14, 14, -10, N'Admin adjustment', '2025-09-29 14:52:58'),
(15, 15, 15, N'Offer completed', '2025-10-07 14:52:58'),
(16, 16, 10, N'Bonus: reducing waste', '2025-09-29 14:52:58'),
(17, 17, 5, N'Admin adjustment', '2025-09-29 14:52:58'),
(18, 18, 5, N'Request fulfilled', '2025-10-01 14:52:58'),
(19, 19, 20, N'Penalty: no-show', '2025-10-04 14:52:58'),
(20, 20, 10, N'Bonus: reducing waste', '2025-10-02 14:52:58'),
(21, 21, -10, N'Penalty: no-show', '2025-10-07 14:52:58'),
(22, 22, -5, N'Admin adjustment', '2025-10-02 14:52:58'),
(23, 23, 15, N'Admin adjustment', '2025-09-28 14:52:58'),
(24, 24, 5, N'Request fulfilled', '2025-10-03 14:52:58'),
(25, 25, -5, N'Penalty: no-show', '2025-10-04 14:52:58'),
(26, 26, -10, N'Penalty: no-show', '2025-09-30 14:52:58'),
(27, 27, 5, N'Penalty: no-show', '2025-10-07 14:52:58'),
(28, 28, 15, N'Admin adjustment', '2025-10-03 14:52:58'),
(29, 29, 5, N'Penalty: no-show', '2025-09-30 14:52:58'),
(30, 30, 5, N'Bonus: reducing waste', '2025-10-01 14:52:58');
SET IDENTITY_INSERT dbo.token_transactions OFF;

-- INSERTS FOR dbo.sensor_readings (30 rows)
SET IDENTITY_INSERT dbo.sensor_readings ON;
INSERT INTO dbo.sensor_readings
(reading_id, household_id, instance_id, sensor_type, reading_value, measured_at) VALUES
(1, 1, 1, N'door_open', 1.0, '2025-10-03 14:52:58'),
(2, 2, 2, N'door_open', 0.0, '2025-10-08 14:52:58'),
(3, 3, 3, N'humidity', 38.69, '2025-10-06 14:52:58'),
(4, 4, 4, N'co2', 722.4, '2025-10-01 14:52:58'),
(5, 5, 5, N'temperature', 2.29, '2025-10-05 14:52:58'),
(6, 6, 6, N'humidity', 41.75, '2025-10-08 14:52:58'),
(7, 7, 7, N'door_open', 1.0, '2025-10-07 14:52:58'),
(8, 8, 8, N'door_open', 0.0, '2025-10-06 14:52:58'),
(9, 9, 9, N'door_open', 0.0, '2025-10-04 14:52:58'),
(10, 10, 10, N'co2', 703.17, '2025-10-01 14:52:58'),
(11, 11, 11, N'door_open', 1.0, '2025-10-06 14:52:58'),
(12, 12, 12, N'door_open', 1.0, '2025-10-06 14:52:58'),
(13, 13, 13, N'temperature', 4.76, '2025-10-02 14:52:58'),
(14, 14, 14, N'co2', 1144.11, '2025-10-04 14:52:58'),
(15, 15, 15, N'temperature', 4.83, '2025-10-04 14:52:58'),
(16, 16, 16, N'door_open', 0.0, '2025-10-01 14:52:58'),
(17, 17, 17, N'door_open', 0.0, '2025-10-02 14:52:58'),
(18, 18, 18, N'door_open', 0.0, '2025-10-05 14:52:58'),
(19, 19, 19, N'humidity', 60.03, '2025-10-05 14:52:58'),
(20, 20, 20, N'door_open', 1.0, '2025-10-01 14:52:58'),
(21, 21, 21, N'door_open', 0.0, '2025-10-06 14:52:58'),
(22, 22, 22, N'door_open', 0.0, '2025-10-06 14:52:58'),
(23, 23, 23, N'co2', 1089.25, '2025-10-01 14:52:58'),
(24, 24, 24, N'temperature', 7.26, '2025-10-01 14:52:58'),
(25, 25, 25, N'temperature', 9.22, '2025-10-02 14:52:58'),
(26, 26, 26, N'humidity', 25.24, '2025-10-04 14:52:58'),
(27, 27, 27, N'co2', 879.77, '2025-10-02 14:52:58'),
(28, 28, 28, N'temperature', 10.52, '2025-10-02 14:52:58'),
(29, 29, 29, N'co2', 882.78, '2025-10-01 14:52:58'),
(30, 30, 30, N'temperature', 8.17, '2025-10-05 14:52:58');
SET IDENTITY_INSERT dbo.sensor_readings OFF;

-- INSERTS FOR dbo.audit_logs (30 rows)
SET IDENTITY_INSERT dbo.audit_logs ON;
INSERT INTO dbo.audit_logs
(log_id, instance_id, event_type, event_detail, created_at) VALUES
(1, 1, N'REPORT', N'{"by":"system","note":"auto log 1"}', '2025-09-29 14:52:58'),
(2, 2, N'STATE_CHANGE', N'{"by":"system","note":"auto log 2"}', '2025-10-06 14:52:58'),
(3, 3, N'WASTE', N'{"by":"system","note":"auto log 3"}', '2025-10-05 14:52:58'),
(4, 4, N'REPORT', N'{"by":"system","note":"auto log 4"}', '2025-10-05 14:52:58'),
(5, 5, N'WASTE', N'{"by":"system","note":"auto log 5"}', '2025-10-03 14:52:58'),
(6, 6, N'REPORT', N'{"by":"system","note":"auto log 6"}', '2025-09-29 14:52:58'),
(7, 7, N'STATE_CHANGE', N'{"by":"system","note":"auto log 7"}', '2025-10-07 14:52:58'),
(8, 8, N'WASTE', N'{"by":"system","note":"auto log 8"}', '2025-10-07 14:52:58'),
(9, 9, N'WASTE', N'{"by":"system","note":"auto log 9"}', '2025-09-27 14:52:58'),
(10, 10, N'WASTE', N'{"by":"system","note":"auto log 10"}', '2025-09-25 14:52:58'),
(11, 11, N'STATE_CHANGE', N'{"by":"system","note":"auto log 11"}', '2025-10-01 14:52:58'),
(12, 12, N'REPORT', N'{"by":"system","note":"auto log 12"}', '2025-09-25 14:52:58'),
(13, 13, N'REPORT', N'{"by":"system","note":"auto log 13"}', '2025-10-03 14:52:58'),
(14, 14, N'STATE_CHANGE', N'{"by":"system","note":"auto log 14"}', '2025-10-03 14:52:58'),
(15, 15, N'STATE_CHANGE', N'{"by":"system","note":"auto log 15"}', '2025-09-19 14:52:58'),
(16, 16, N'WASTE', N'{"by":"system","note":"auto log 16"}', '2025-09-19 14:52:58'),
(17, 17, N'REPORT', N'{"by":"system","note":"auto log 17"}', '2025-10-01 14:52:58'),
(18, 18, N'WASTE', N'{"by":"system","note":"auto log 18"}', '2025-09-20 14:52:58'),
(19, 19, N'STATE_CHANGE', N'{"by":"system","note":"auto log 19"}', '2025-10-01 14:52:58'),
(20, 20, N'WASTE', N'{"by":"system","note":"auto log 20"}', '2025-09-18 14:52:58'),
(21, 21, N'WASTE', N'{"by":"system","note":"auto log 21"}', '2025-09-24 14:52:58'),
(22, 22, N'WASTE', N'{"by":"system","note":"auto log 22"}', '2025-10-08 14:52:58'),
(23, 23, N'WASTE', N'{"by":"system","note":"auto log 23"}', '2025-09-29 14:52:58'),
(24, 24, N'REPORT', N'{"by":"system","note":"auto log 24"}', '2025-09-21 14:52:58'),
(25, 25, N'STATE_CHANGE', N'{"by":"system","note":"auto log 25"}', '2025-10-06 14:52:58'),
(26, 26, N'WASTE', N'{"by":"system","note":"auto log 26"}', '2025-09-27 14:52:58'),
(27, 27, N'REPORT', N'{"by":"system","note":"auto log 27"}', '2025-09-29 14:52:58'),
(28, 28, N'REPORT', N'{"by":"system","note":"auto log 28"}', '2025-09-25 14:52:58'),
(29, 29, N'REPORT', N'{"by":"system","note":"auto log 29"}', '2025-09-30 14:52:58'),
(30, 30, N'WASTE', N'{"by":"system","note":"auto log 30"}', '2025-09-29 14:52:58');
SET IDENTITY_INSERT dbo.audit_logs OFF;




SELECT user_id, name, email, phone, created_at
FROM dbo.users
ORDER BY created_at DESC;

-- 2) Gmail users only
SELECT user_id, name, email
FROM dbo.users
WHERE email LIKE N'%@gmail.%';

-- 3) Users by zone (JOIN households → zones)
SELECT z.name AS zone_name, COUNT(*) AS users_in_zone
FROM dbo.users u
JOIN dbo.households h ON h.household_id = u.household_id
JOIN dbo.zones z       ON z.zone_id       = h.zone_id
GROUP BY z.name
ORDER BY users_in_zone DESC;

-- 4) Newest user per zone (window function)
WITH ranked AS (
  SELECT u.user_id, u.name, z.name AS zone_name, u.created_at,
         ROW_NUMBER() OVER (PARTITION BY z.zone_id ORDER BY u.created_at DESC) AS rn
  FROM dbo.users u
  JOIN dbo.households h ON h.household_id = u.household_id
  JOIN dbo.zones z       ON z.zone_id       = h.zone_id
)
SELECT * FROM ranked WHERE rn = 1;

-- 5) Token balance per user
SELECT u.user_id, u.name, COALESCE(SUM(t.delta),0) AS token_balance
FROM dbo.users u
LEFT JOIN dbo.token_transactions t ON t.user_id = u.user_id
GROUP BY u.user_id, u.name
ORDER BY token_balance DESC;

-- 6) Running token balance over time (window SUM)
SELECT
  u.user_id, u.name, t.created_at, t.delta,
  SUM(t.delta) OVER (PARTITION BY u.user_id ORDER BY t.created_at
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance
FROM dbo.users u
JOIN dbo.token_transactions t ON t.user_id = u.user_id
ORDER BY u.user_id, t.created_at;

-- 7) Anti-join: users with no offers or requests
SELECT u.user_id, u.name
FROM dbo.users u
WHERE NOT EXISTS (SELECT 1 FROM dbo.offers   o WHERE o.offered_by   = u.user_id)
  AND NOT EXISTS (SELECT 1 FROM dbo.requests r WHERE r.requested_by = u.user_id);


/* ============================================================
   ITEMS — Basic to Advanced
   ============================================================ */
-- 1) Search by category
SELECT item_id, sku, name, category
FROM dbo.items
WHERE category = N'Dairy'
ORDER BY name;

-- 2) Most requested items
SELECT i.item_id, i.name, COUNT(*) AS total_requests
FROM dbo.items i
JOIN dbo.requests r ON r.item_id = i.item_id
GROUP BY i.item_id, i.name
ORDER BY total_requests DESC;

-- 3) Pivot: requests count per status by category
SELECT *
FROM (
  SELECT i.category, r.status, 1 AS cnt
  FROM dbo.items i
  JOIN dbo.requests r ON r.item_id = i.item_id
) s
PIVOT (SUM(cnt) FOR status IN ([open],[matched],[closed])) p
ORDER BY category;


/* ============================================================
   ZONES — Basic
   ============================================================ */
-- 1) Zones with household counts
SELECT z.zone_id, z.name,
       COUNT(h.household_id) AS households_in_zone
FROM dbo.zones z
LEFT JOIN dbo.households h ON h.zone_id = z.zone_id
GROUP BY z.zone_id, z.name
ORDER BY z.zone_id;

-- 2) Approx nearby zones within ~5km (bounding box demo)
DECLARE @lat DECIMAL(9,6) = 41.390000;
DECLARE @lng DECIMAL(9,6) = 2.170000;
SELECT zone_id, name, center_lat, center_lng
FROM dbo.zones
WHERE center_lat BETWEEN @lat - 0.045 AND @lat + 0.045
  AND center_lng BETWEEN @lng - 0.060 AND @lng + 0.060;


/* ============================================================
   HOUSEHOLDS — Basic to Intermediate
   ============================================================ */
-- 1) Newly created in last 14 days
SELECT household_id, address, created_at
FROM dbo.households
WHERE created_at >= DATEADD(DAY, -14, SYSUTCDATETIME())
ORDER BY created_at DESC;

-- 2) Households without any users
SELECT h.household_id, h.address
FROM dbo.households h
LEFT JOIN dbo.users u ON u.household_id = h.household_id
WHERE u.user_id IS NULL;

-- 3) Temperature breaches in last 7 days
SELECT h.household_id, h.address, COUNT(*) AS high_temp_events
FROM dbo.households h
JOIN dbo.sensor_readings s ON s.household_id = h.household_id
WHERE s.sensor_type = N'temperature'
  AND s.reading_value > 8.0
  AND s.measured_at >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY h.household_id, h.address
ORDER BY high_temp_events DESC;


/* ============================================================
   ITEM_INSTANCES — Basic to Advanced
   ============================================================ */
-- 1) Expiring in next 3 days & available
SELECT ii.instance_id, i.name, ii.estimated_expiry, h.address
FROM dbo.item_instances ii
JOIN dbo.items i       ON i.item_id = ii.item_id
JOIN dbo.households h  ON h.household_id = ii.household_id
WHERE ii.state = N'available'
  AND ii.estimated_expiry BETWEEN CAST(SYSUTCDATETIME() AS DATE)
                              AND DATEADD(DAY, 3, CAST(SYSUTCDATETIME() AS DATE))
ORDER BY ii.estimated_expiry;

-- 2) Days to expiry + risk quartile
WITH data AS (
  SELECT ii.instance_id, i.name,
         DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), ii.estimated_expiry) AS days_to_expiry
  FROM dbo.item_instances ii
  JOIN dbo.items i ON i.item_id = ii.item_id
)
SELECT *, NTILE(4) OVER (ORDER BY days_to_expiry) AS risk_quartile
FROM data
ORDER BY days_to_expiry;

-- 3) Preview overdue items (and optional update)
SELECT instance_id, state, estimated_expiry
FROM dbo.item_instances
WHERE state <> N'wasted' AND estimated_expiry < CAST(SYSUTCDATETIME() AS DATE);
/*
-- If OK, mark as wasted:
UPDATE dbo.item_instances
SET state = N'wasted'
WHERE state <> N'wasted' AND estimated_expiry < CAST(SYSUTCDATETIME() AS DATE);
*/


/* ============================================================
   OFFERS — Basic to Advanced
   ============================================================ */
-- 1) Open offers expiring within 48 hours
SELECT o.offer_id, i.name, o.valid_until, h.address
FROM dbo.offers o
JOIN dbo.item_instances ii ON ii.instance_id = o.instance_id
JOIN dbo.items i           ON i.item_id      = ii.item_id
JOIN dbo.households h      ON h.household_id = ii.household_id
WHERE o.status = N'open'
  AND o.valid_until BETWEEN SYSUTCDATETIME() AND DATEADD(HOUR, 48, SYSUTCDATETIME())
ORDER BY o.valid_until;

-- 2) Offer → Exchange details
SELECT o.offer_id, i.name, e.exchange_time, e.status AS exchange_status,
       giver.name AS giver_name, receiver.name AS receiver_name
FROM dbo.offers o
LEFT JOIN dbo.exchanges e       ON e.offer_id = o.offer_id
JOIN dbo.item_instances ii      ON ii.instance_id = o.instance_id
JOIN dbo.items i                ON i.item_id = ii.item_id
LEFT JOIN dbo.users giver       ON giver.user_id   = e.giver_user_id
LEFT JOIN dbo.users receiver    ON receiver.user_id= e.receiver_user_id
ORDER BY o.offer_id;


/* ============================================================
   REQUESTS — Basic to Advanced
   ============================================================ */
-- 1) Open requests with item name
SELECT r.request_id, u.name AS requester, i.name AS item, r.desired_quantity, r.created_at
FROM dbo.requests r
JOIN dbo.users u ON u.user_id = r.requested_by
JOIN dbo.items i ON i.item_id = r.item_id
WHERE r.status = N'open'
ORDER BY r.created_at DESC;

-- 2) Find nearest matching offers (Haversine via CROSS APPLY)
DECLARE @R FLOAT = 6371.0; -- Earth radius (km)
DECLARE @maxKm FLOAT = 5.0;
WITH req AS (
  SELECT r.request_id, r.item_id, r.requested_by, r.status,
         hh.geo_lat AS r_lat, hh.geo_lng AS r_lng
  FROM dbo.requests r
  JOIN dbo.users u   ON u.user_id = r.requested_by
  JOIN dbo.households hh ON hh.household_id = u.household_id
  WHERE r.status = N'open'
)
SELECT TOP 20
  req.request_id, i.name AS item_name, o.offer_id,
  distance_km, offer_addr, o.status AS offer_status
FROM req
JOIN dbo.items i ON i.item_id = req.item_id
JOIN dbo.offers o ON o.status = N'open'
JOIN dbo.item_instances ii ON ii.instance_id = o.instance_id AND ii.item_id = req.item_id
JOIN dbo.households ho ON ho.household_id = ii.household_id
CROSS APPLY (
  SELECT
    @R * ACOS(
      COS(RADIANS(req.r_lat)) * COS(RADIANS(ho.geo_lat)) * COS(RADIANS(ho.geo_lng - req.r_lng)) +
      SIN(RADIANS(req.r_lat)) * SIN(RADIANS(ho.geo_lat))
    ) AS distance_km,
    ho.address AS offer_addr
) d
WHERE d.distance_km <= @maxKm
ORDER BY distance_km ASC;


/* ============================================================
   EXCHANGES — Basic to Advanced
   ============================================================ */
-- 1) Completed in last 30 days
SELECT COUNT(*) AS total_completed
FROM dbo.exchanges
WHERE status = N'completed'
  AND exchange_time >= DATEADD(DAY, -30, SYSUTCDATETIME());

-- 2) Summary by status with ROLLUP
SELECT status, COUNT(*) AS cnt
FROM dbo.exchanges
GROUP BY ROLLUP(status);

-- 3) Top giver/receiver pairs
SELECT TOP 10
  g.name AS giver, rcv.name AS receiver, COUNT(*) AS total
FROM dbo.exchanges e
JOIN dbo.users g   ON g.user_id   = e.giver_user_id
JOIN dbo.users rcv ON rcv.user_id = e.receiver_user_id
GROUP BY g.name, rcv.name
ORDER BY total DESC;


/* ============================================================
   TOKEN_TRANSACTIONS — Basic to Advanced
   ============================================================ */
-- 1) Monthly summary
SELECT
  YEAR(created_at) AS yr, MONTH(created_at) AS mo,
  SUM(CASE WHEN delta>0 THEN delta ELSE 0 END) AS total_earned,
  SUM(CASE WHEN delta<0 THEN -delta ELSE 0 END) AS total_spent,
  SUM(delta) AS net_change
FROM dbo.token_transactions
GROUP BY YEAR(created_at), MONTH(created_at)
ORDER BY yr DESC, mo DESC;

-- 2) Users with negative net tokens
SELECT u.user_id, u.name, SUM(t.delta) AS net_tokens
FROM dbo.users u
JOIN dbo.token_transactions t ON t.user_id = u.user_id
GROUP BY u.user_id, u.name
HAVING SUM(t.delta) < 0
ORDER BY net_tokens ASC;


/* ============================================================
   SENSOR_READINGS — Basic to Advanced
   ============================================================ */
-- 1) Last reading per household per sensor type
WITH ranked AS (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.household_id, s.sensor_type ORDER BY s.measured_at DESC) AS rn
  FROM dbo.sensor_readings s
)
SELECT household_id, sensor_type, reading_value, measured_at
FROM ranked
WHERE rn = 1
ORDER BY household_id, sensor_type;

-- 2) Average temperature by day (last 7 days)
SELECT CAST(measured_at AS DATE) AS [date],
       AVG(reading_value) AS avg_temp_c
FROM dbo.sensor_readings
WHERE sensor_type = N'temperature'
  AND measured_at >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY CAST(measured_at AS DATE)
ORDER BY [date];

-- 3) Pivot by sensor_type
SELECT *
FROM (
  SELECT household_id, sensor_type, reading_value
  FROM dbo.sensor_readings
  WHERE measured_at >= DATEADD(DAY, -3, SYSUTCDATETIME())
) s
PIVOT (AVG(reading_value) FOR sensor_type IN ([temperature],[humidity],[co2],[door_open])) p
ORDER BY household_id;


/* ============================================================
   AUDIT_LOGS — Basic to Advanced
   ============================================================ */
-- 1) Recent events
SELECT TOP 50 log_id, instance_id, event_type, created_at
FROM dbo.audit_logs
ORDER BY created_at DESC;

-- 2) JSON value extraction (if valid JSON stored)
SELECT log_id, instance_id,
       JSON_VALUE(event_detail, '$.note') AS note,
       created_at
FROM dbo.audit_logs
WHERE ISJSON(event_detail) = 1
ORDER BY created_at DESC;


/* ============================================================
   ADVANCED — Helpful views (create once)
   ============================================================ */
-- A) Offers joined with item, household, and exchange
CREATE OR ALTER VIEW dbo.v_offers_enriched AS
SELECT
  o.offer_id,
  o.status AS offer_status,
  o.valid_until,
  i.item_id, i.name AS item_name, i.category,
  ii.instance_id, ii.state AS instance_state, ii.estimated_expiry,
  h.household_id, h.address, z.name AS zone_name,
  e.exchange_id, e.status AS exchange_status, e.exchange_time,
  giver.name   AS giver_name,
  receiver.name AS receiver_name
FROM dbo.offers o
JOIN dbo.item_instances ii ON ii.instance_id = o.instance_id
JOIN dbo.items i           ON i.item_id      = ii.item_id
JOIN dbo.households h      ON h.household_id = ii.household_id
JOIN dbo.zones z           ON z.zone_id      = h.zone_id
LEFT JOIN dbo.exchanges e  ON e.offer_id     = o.offer_id
LEFT JOIN dbo.users giver   ON giver.user_id   = e.giver_user_id
LEFT JOIN dbo.users receiver ON receiver.user_id= e.receiver_user_id;
GO

-- B) User token balances view
CREATE OR ALTER VIEW dbo.v_user_token_balance AS
SELECT u.user_id, u.name, COALESCE(SUM(t.delta),0) AS token_balance
FROM dbo.users u
LEFT JOIN dbo.token_transactions t ON t.user_id = u.user_id
GROUP BY u.user_id, u.name;
GO

-- C) Expiring & available items view
CREATE OR ALTER VIEW dbo.v_expiring_available AS
SELECT
  ii.instance_id, i.name AS item_name, ii.estimated_expiry, ii.state,
  h.household_id, h.zone_id
FROM dbo.item_instances ii
JOIN dbo.items i ON i.item_id = ii.item_id
JOIN dbo.households h ON h.household_id = ii.household_id
WHERE ii.state = N'available' AND ii.estimated_expiry IS NOT NULL;
GO


/* ============================================================
   ADVANCED — Master analytics (multi-joins)
   ============================================================ */
-- 1) Requests matched to nearest open offers within X km (parameterized)
DECLARE @MaxKm FLOAT = 5.0, @EarthKm FLOAT = 6371.0;
WITH R AS (
  SELECT r.request_id, r.item_id, r.requested_by, r.status,
         uh.geo_lat AS r_lat, uh.geo_lng AS r_lng
  FROM dbo.requests r
  JOIN dbo.users u  ON u.user_id = r.requested_by
  JOIN dbo.households uh ON uh.household_id = u.household_id
  WHERE r.status = N'open'
)
SELECT TOP 50
  R.request_id, iu.name AS requester,
  it.name AS item_name,
  O.offer_id, H.address AS offer_address,
  D.distance_km
FROM R
JOIN dbo.items it ON it.item_id = R.item_id
JOIN dbo.offers O ON O.status = N'open'
JOIN dbo.item_instances II ON II.instance_id = O.instance_id AND II.item_id = R.item_id
JOIN dbo.households H ON H.household_id = II.household_id
JOIN dbo.users iu ON iu.user_id = R.requested_by
CROSS APPLY (
  SELECT
    @EarthKm * ACOS(
      COS(RADIANS(R.r_lat)) * COS(RADIANS(H.geo_lat)) * COS(RADIANS(H.geo_lng - R.r_lng)) +
      SIN(RADIANS(R.r_lat)) * SIN(RADIANS(H.geo_lat))
    ) AS distance_km
) D
WHERE D.distance_km <= @MaxKm
ORDER BY D.distance_km ASC;
GO

-- 2) Daily KPIs with GROUPING SETS
SELECT
  CAST(e.exchange_time AS DATE) AS [date],
  e.status,
  COUNT(*) AS exchanges
FROM dbo.exchanges e
GROUP BY GROUPING SETS (
  (CAST(e.exchange_time AS DATE), e.status),
  (CAST(e.exchange_time AS DATE)),
  (e.status),
  ()
)
ORDER BY [date] ASC, status;
GO

-- 3) User activity summary (offers, requests, exchanges)
SELECT
  u.user_id, u.name,
  COALESCE(o_cnt,0) AS offers_made,
  COALESCE(r_cnt,0) AS requests_made,
  COALESCE(e_give,0) AS exchanges_as_giver,
  COALESCE(e_recv,0) AS exchanges_as_receiver
FROM dbo.users u
LEFT JOIN (
  SELECT offered_by AS user_id, COUNT(*) AS o_cnt
  FROM dbo.offers GROUP BY offered_by
) o ON o.user_id = u.user_id
LEFT JOIN (
  SELECT requested_by AS user_id, COUNT(*) AS r_cnt
  FROM dbo.requests GROUP BY requested_by
) r ON r.user_id = u.user_id
LEFT JOIN (
  SELECT giver_user_id AS user_id, COUNT(*) AS e_give
  FROM dbo.exchanges GROUP BY giver_user_id
) eg ON eg.user_id = u.user_id
LEFT JOIN (
  SELECT receiver_user_id AS user_id, COUNT(*) AS e_recv
  FROM dbo.exchanges GROUP BY receiver_user_id
) er ON er.user_id = u.user_id
ORDER BY (COALESCE(o_cnt,0)+COALESCE(r_cnt,0)+COALESCE(e_give,0)+COALESCE(e_recv,0)) DESC;
GO