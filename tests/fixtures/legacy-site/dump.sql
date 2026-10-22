SET NAMES utf8mb4;
CREATE TABLE pages (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  slug VARCHAR(190) NOT NULL UNIQUE,
  title VARCHAR(255) NOT NULL,
  body MEDIUMTEXT NOT NULL,
  published TINYINT(1) NOT NULL DEFAULT 1,
  updated_at DATETIME NOT NULL
) DEFAULT CHARSET=utf8mb4;
CREATE TABLE news (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  slug VARCHAR(190) NOT NULL,
  title VARCHAR(255) NOT NULL,
  summary TEXT NULL,
  body MEDIUMTEXT NOT NULL,
  published_at DATETIME NULL,
  author_id INT UNSIGNED NULL
) DEFAULT CHARSET=utf8mb4;
CREATE TABLE users (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(190) NOT NULL UNIQUE,
  display_name VARCHAR(190) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('admin','editor') NOT NULL DEFAULT 'editor',
  created_at DATETIME NOT NULL
) DEFAULT CHARSET=utf8mb4;
CREATE TABLE contact_messages (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(190) NOT NULL, email VARCHAR(190) NOT NULL, message TEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) DEFAULT CHARSET=utf8mb4;
INSERT INTO pages (id, slug, title, body, published, updated_at) VALUES
 (1, 'home', 'Welkom bij de gemeente', '<p>Openingstijden: ma–vr 9:00–17:00.</p>', 1, '2024-03-01 10:15:00'),
 (2, 'afval', 'Afval & recycling', '<p>Zet de "groene" container op dinsdag buiten.\nVragen? Bel 14 020.</p>', 1, '2025-01-12 08:00:00'),
 (3, 'concept-beleid', 'Concept: beleid 2026', '<p>Nog niet publiceren \\ intern</p>', 0, '2026-09-30 16:45:00'),
 (4, 'english', 'Résidents & visitors – Ünïcode ✓ 🚲', '<p>It''s easy: “quotes”, tabs\tand backslashes \\ here.</p>', 1, '2023-07-04 12:00:00');
INSERT INTO news (id, slug, title, summary, body, published_at, author_id) VALUES
 (12, 'raadsbesluit-fietspad', 'Raad stemt in met nieuw fietspad', 'Het fietspad komt er.', '<p>De gemeenteraad heeft ingestemd.</p>', '2019-04-11 19:30:00', 1),
 (13, 'werkzaamheden-markt', 'Werkzaamheden op de Markt', NULL, '<p>Van 1 t/m 5 mei.</p>', '2026-10-01 09:00:00', NULL),
 (14, 'concept-nieuws', 'Nog niet gepubliceerd', NULL, '<p>draft</p>', NULL, 2);
INSERT INTO users (id, email, display_name, password_hash, role, created_at) VALUES
 (1, 'Admin@Gemeente.example', 'Beheerder', '$2y$10$abcdefghijklmnopqrstuuJ1h9a8ZsY0x4VtF1sJx5E7p6r8m2Kq', 'admin', '2018-01-01 00:00:00'),
 (2, 'redactie@gemeente.example', 'Redactie', '$2y$10$zyxwvutsrqponmlkjihgfeKsLq1Y2wE9rT8yU7iO6pA5sD4fG3hJ', 'editor', '2020-05-05 12:00:00');
INSERT INTO contact_messages (name, email, message, created_at) VALUES
 ('Jan Jansen', 'jan@example.nl', 'Mijn container is niet geleegd.', '2026-09-01 10:00:00');
