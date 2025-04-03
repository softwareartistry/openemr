<?php
// Secret token from GitHub webhook
$secret = "your_webhook_secret";

// Validate request is from GitHub
$headers = getallheaders();
$signature = $headers['X-Hub-Signature'] ?? '';

if ($signature) {
    $payload = file_get_contents('php://input');
    list($algo, $hash) = explode('=', $signature, 2);
    $payloadHash = hash_hmac($algo, $payload, $secret);
    
    if (hash_equals($hash, $payloadHash)) {
        // Pull latest changes
        exec('cd /var/www/openemr-integration && git pull');
        
        // Restart container to apply changes
        exec('cd /var/www/openemr-integration && docker-compose -f docker-compose.integration.yml restart openemr');
        
        http_response_code(200);
        echo "Deployment triggered successfully";
    } else {
        http_response_code(403);
        echo "Invalid signature";
    }
} else {
    http_response_code(403);
    echo "No signature found";
} 