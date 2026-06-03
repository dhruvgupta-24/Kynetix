# test_free_vision.ps1 - Test specific free vision models only

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="

$headers = @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix" }

function Test-VisionModel($modelId) {
    Write-Host "--- Testing: $modelId ---" -ForegroundColor Yellow
    $body = @{
        model = $modelId
        messages = @(
            @{ role = "user"; content = @(
                @{ type = "text"; text = "What food is in this image? Just say 'image received' if you cannot see clearly." }
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
            )}
        )
        max_tokens = 100
        stream = $false
    } | ConvertTo-Json -Depth 10
    
    try {
        $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 30 -ErrorAction Stop
        $content = ($r.Content | ConvertFrom-Json).choices[0].message.content
        Write-Host "  SUCCESS: $content" -ForegroundColor Green
        return $true
    } catch {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $err = $reader.ReadToEnd()
            $code = $_.Exception.Response.StatusCode.value__
            Write-Host "  FAIL ($code): $($err.Substring(0, [Math]::Min(200, $err.Length)))" -ForegroundColor Red
        } else {
            Write-Host "  TIMEOUT/ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $false
    }
}

$models = @(
    "meta-llama/llama-4-scout:free",
    "qwen/qwen2-vl-7b-instruct:free",
    "google/gemini-2.0-flash-exp:free",
    "mistralai/mistral-small-3.1-24b-instruct:free",
    "moonshotai/kimi-vl-a3b-thinking:free"
)

$winner = $null
foreach ($m in $models) {
    if (Test-VisionModel $m) {
        $winner = $m
        break
    }
}

Write-Host ""
if ($winner) {
    Write-Host "=== WINNER: Use $winner as OPENROUTER_VISION_MODEL ===" -ForegroundColor Green
} else {
    Write-Host "=== All free models failed. Need to top up OpenRouter credits. ===" -ForegroundColor Red
}
