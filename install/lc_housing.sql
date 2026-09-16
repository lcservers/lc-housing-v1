-- LC Housing database schema
-- Created by LC

CREATE TABLE IF NOT EXISTS `lc_houses` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `label` varchar(96) NOT NULL,
  `price` int(11) NOT NULL DEFAULT 0,
  `property_type` varchar(16) NOT NULL DEFAULT 'shell',
  `shell` varchar(64) DEFAULT NULL,
  `ipl` varchar(96) DEFAULT NULL,
  `mlo` varchar(96) DEFAULT NULL,
  `image` text DEFAULT NULL,
  `owner` varchar(64) DEFAULT NULL,
  `owned` tinyint(1) NOT NULL DEFAULT 0,
  `coords` longtext NOT NULL,
  `polyzone` longtext DEFAULT NULL,
  `interior` longtext DEFAULT NULL,
  `settings` longtext DEFAULT NULL,
  `created_by` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
