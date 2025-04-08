<?php
// Sample user data
$users = [
    ['id' => 1, 'name' => 'Siva', 'email' => 'siva@example.com'],
    ['id' => 2, 'name' => 'Arun', 'email' => 'arun@example.com'],
];

// Display users
echo "<h2>User List:</h2>";
echo "<ul>";
foreach ($users as $user) {
    echo "<li>ID: {$user['id']} | Name: {$user['name']} | Email: {$user['email']}</li>";
}
echo "</ul>";
?>
