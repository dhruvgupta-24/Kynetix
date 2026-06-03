# list_free_vision_models.ps1 - Get actual free vision model IDs from OpenRouter API

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"

Write-Host "Fetching model list from OpenRouter..." -ForegroundColor Cyan

try {
    $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/models" -Method GET -TimeoutSec 20 -ErrorAction Stop
    $json = $r.Content | ConvertFrom-Json
    
    Write-Host "Total models: $($json.data.Count)"
    Write-Host ""
    Write-Host "=== Free models with image support ===" -ForegroundColor Green
    
    foreach ($m in $json.data) {
        # Price of 0 means free
        $isFreePricing = $m.pricing.prompt -eq 0 -or $m.pricing.prompt -eq "0"
        
        # Check if model supports image inputs
        $hasImageInput = $false
        if ($m.architecture.input_modalities) {
            $hasImageInput = $m.architecture.input_modalities -contains "image"
        }
        
        if ($isFreePricing -and $hasImageInput) {
            Write-Host "  Model: $($m.id)"
            Write-Host "  Name: $($m.name)"
            Write-Host "  Modalities: $($m.architecture.input_modalities -join ', ')"
            Write-Host "  Price(prompt): $($m.pricing.prompt)"
            Write-Host ""
        }
    }
    
    Write-Host "=== Top 20 cheapest models with image support ===" -ForegroundColor Yellow
    $cheapVision = $json.data | Where-Object { 
        $_.architecture.input_modalities -contains "image" 
    } | Sort-Object { [double]($_.pricing.prompt) } | Select-Object -First 20
    
    foreach ($m in $cheapVision) {
        Write-Host "  $($m.id) | prompt_price=$($m.pricing.prompt)"
    }
    
} catch {
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red
    } else {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
