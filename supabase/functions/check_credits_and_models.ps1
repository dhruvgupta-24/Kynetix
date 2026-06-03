# check_credits_and_models.ps1
$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="

Write-Host "=== Credits ===" -ForegroundColor Cyan
try {
    $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/auth/key" -Method GET -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY" } -ErrorAction Stop
    $r.Content | ConvertFrom-Json | Format-List
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Test meta-llama/llama-4-scout:free (free vision) ===" -ForegroundColor Cyan
$b = @{ model = "meta-llama/llama-4-scout:free"; messages = @(@{ role = "system"; content = "You are a food analyzer." }, @{ role = "user"; content = @(@{ type = "text"; text = "What food?" }, @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }) }); temperature = 0.25; max_tokens = 500; stream = $false } | ConvertTo-Json -Depth 10
try {
    $r2 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix" } -Body $b -ErrorAction Stop
    Write-Host "SUCCESS: $($r2.Content.Substring(0, 400))" -ForegroundColor Green
} catch {
    if ($_.Exception.Response) { $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red } else { Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host ""
Write-Host "=== Test qwen/qwen2-vl-7b-instruct:free (free vision) ===" -ForegroundColor Cyan
$b3 = @{ model = "qwen/qwen2-vl-7b-instruct:free"; messages = @(@{ role = "user"; content = @(@{ type = "text"; text = "What food is in this image?" }, @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }) }); temperature = 0.25; max_tokens = 500; stream = $false } | ConvertTo-Json -Depth 10
try {
    $r3 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix" } -Body $b3 -ErrorAction Stop
    Write-Host "SUCCESS: $($r3.Content.Substring(0, 400))" -ForegroundColor Green
} catch {
    if ($_.Exception.Response) { $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red } else { Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red }
}
