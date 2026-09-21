# Windows equivalent of stage_data.sh: copies the two hackathon CSVs into resources/data/.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path resources/data | Out-Null
foreach ($f in @("rat_sightings.csv", "restaurant_inspections.csv")) {
  Copy-Item -Path "hackathon-materials/$f" -Destination "resources/data/$f" -Force
  Write-Host "copied hackathon-materials/$f -> resources/data/$f"
}
Get-ChildItem resources/data
