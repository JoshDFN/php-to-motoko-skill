<?php
session_start();
if (($_SESSION['role'] ?? '') !== 'admin') { http_response_code(403); exit; }
$target = __DIR__ . '/../uploads/' . date('Y') . '/' . basename($_FILES['file']['name']);
move_uploaded_file($_FILES['file']['tmp_name'], $target);
$img = imagecreatefromjpeg($target);
