<?php
require 'lib/db.php';
session_start();
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($_POST['csrf'] !== $_SESSION['csrf']) { http_response_code(400); exit; }
    db()->prepare('INSERT INTO contact_messages (name, email, message) VALUES (?, ?, ?)')
        ->execute([$_POST['name'], $_POST['email'], $_POST['message']]);
    mail('info@gemeente.example', 'Nieuw contactformulier', $_POST['message']);
}
