<?php
require 'lib/db.php';
session_start();
$slug = $_GET['page'] ?? 'home';
$stmt = db()->prepare('SELECT title, body FROM pages WHERE slug = ? AND published = 1');
$stmt->execute([$slug]);
$page = $stmt->fetch();
include 'header.php';
echo '<h1>' . htmlspecialchars($page['title']) . '</h1>' . $page['body'];
