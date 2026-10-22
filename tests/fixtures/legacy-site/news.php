<?php
require 'lib/db.php';
$id = (int)($_GET['id'] ?? 0);
$stmt = db()->prepare('SELECT * FROM news WHERE id = ?');
$stmt->execute([$id]);
$item = $stmt->fetch();
echo '<h1>' . htmlspecialchars($item['title']) . '</h1>' . $item['body'];
