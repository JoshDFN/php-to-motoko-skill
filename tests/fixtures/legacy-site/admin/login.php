<?php
require '../lib/db.php';
session_start();
$stmt = db()->prepare('SELECT id, password_hash, role FROM users WHERE email = ?');
$stmt->execute([$_POST['email']]);
$u = $stmt->fetch();
if ($u && password_verify($_POST['password'], $u['password_hash'])) {
    $_SESSION['user_id'] = $u['id'];
    $_SESSION['role'] = $u['role'];
}
