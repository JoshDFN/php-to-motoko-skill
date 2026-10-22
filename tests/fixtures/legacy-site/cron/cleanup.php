<?php
require __DIR__ . '/../lib/db.php';
db()->exec('DELETE FROM contact_messages WHERE created_at < NOW() - INTERVAL 1 YEAR');
$client = new \GuzzleHttp\Client();
$client->post('https://api.example-mail.nl/v1/digest', ['json' => ['count' => 3]]);
