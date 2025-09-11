<#
.SYNOPSIS
  Regenerates remaining future roadmap derived blocks (flattened list & policy matrix) from features.json.
.DESCRIPTION
  Simplified after Horizon section removal.
  Uses manifest to:
   - Partition features (retained internally; Near table suppressed by design)
   - Generate flattened list of features
   - Generate policy coverage matrix (union of policy keys across features)
  Writes into README.md markers:
    FUTURE_NEAR (if present), FLATTENED_FEATURES, POLICY_MATRIX
#>
param(
  [int]$NearWindowDays = 60
)
$ErrorActionPreference='Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$readme = Join-Path $root 'README.md'
$manifestPath = Join-Path $root 'features.json'
if(-not (Test-Path $manifestPath)){ throw 'features.json not found' }
$features = Get-Content $manifestPath -Raw | ConvertFrom-Json
$now = Get-Date

function Parse-Date($val){
  if(-not $val){ return $null }
  $formats = 'yyyy-MM-dd','yyyy-MM','yyyy-MM-ddTHH:mm:ss'
  foreach($f in $formats){
    [DateTime]$parsed = [DateTime]::MinValue
    if([DateTime]::TryParseExact($val,$f,$null,[System.Globalization.DateTimeStyles]::None,[ref]$parsed)){
      return $parsed
    }
  }
  [DateTime]$generic = [DateTime]::MinValue
  if([DateTime]::TryParse($val,[ref]$generic)){
    return $generic
  }
  return $null
}

# Derive helper properties
foreach($f in $features){
  $f | Add-Member -NotePropertyName plannedDateObj -NotePropertyValue (Parse-Date $f.plannedGA) -Force
  $f | Add-Member -NotePropertyName decisionDateObj -NotePropertyValue (Parse-Date $f.decisionNeededBy) -Force
  $f | Add-Member -NotePropertyName previewStartObj -NotePropertyValue (Parse-Date $f.previewStart) -Force
  $f | Add-Member -NotePropertyName lastUpdateObj -NotePropertyValue (Parse-Date $f.lastUpdate) -Force
}

$nearCutoff = $now.AddDays($NearWindowDays)

$near = $features |
  Where-Object {
    ($_.plannedDateObj -and $_.plannedDateObj -le $nearCutoff) -or
    ($_.decisionDateObj -and $_.decisionDateObj -le $nearCutoff)
  } |
  Sort-Object -Property @{ Expression = { if ($_.plannedDateObj) { 0 } else { 1 } }; Ascending = $true }, @{ Expression = { $_.plannedDateObj }; Ascending = $true }, @{ Expression = { $_.decisionDateObj }; Ascending = $true }

$nearSlugs = $near.slug
$horizon = $features | Where-Object { $nearSlugs -notcontains $_.slug }

function Format-StatusGlyph($s){
  if($s -match '^GA') { return '✅ ' + $s }
  if($s -match 'Preview') { return '🧪 ' + $s }
  if($s -match 'enhanc' -or $s -match 'Enhancing') { return '🔍 ' + $s }
  return $s
}

function Build-NearTable($items){
  $header = '| Item (Summary) | Target | Status | Why It Matters | Immediate Prep | Decision Needed By |'
  $sep =    '|----------------|--------|--------|----------------|----------------|--------------------|'
  $rows = foreach($f in $items){
    $target = if($f.plannedGA){ if($f.plannedGA -eq 'TBD'){ 'TBD' } else { $f.plannedGA } } else { '' }
    $status = Format-StatusGlyph $f.currentStatus
    $prepDate = if($f.decisionDateObj){ $f.decisionDateObj.ToString('yyyy-MM-dd') } else { '' }
  $disp = if($f.docUrl){ "[$($f.name)]($($f.docUrl))" } else { $f.name }
  "| $disp | $target | $status | $($f.purpose) | (auto) | $prepDate |"
  }
  return ($header,$sep)+$rows -join "`n"
}

 $nearTable = Build-NearTable $near


# Flattened list
$flatList = $features | Sort-Object name | ForEach-Object {
  $glyph = if($_.lifecycleStage -eq 'GA'){ '✅' } elseif($_.lifecycleStage -eq 'Preview'){ '🧪' } elseif($_.lifecycleStage -match 'Enhancing'){ '🔍' } else { '📅' }
  $disp = if($_.docUrl){ "[$($_.name)]($($_.docUrl))" } else { $_.name }
  "- $disp ($glyph $($_.lifecycleStage))"
} | Out-String

 # Feature IDs section removed from README; IDs still derivable on demand.

# Policy matrix
$allPolicyKeys = $features | ForEach-Object { $_.policies.PSObject.Properties.Name } | Where-Object { $_ } | Sort-Object -Unique
$policyHeader = '| Feature | ' + ($allPolicyKeys -join ' | ') + ' |'
$policySep = '|---------|' + ($allPolicyKeys | ForEach-Object { '-----|' }) -join ''
$policyRows = foreach($f in $features){
  $cells = foreach($k in $allPolicyKeys){ if($f.policies -and $f.policies.$k){ '✓' } else { '–' } }
  $disp = if($f.docUrl){ "[$($f.name)]($($f.docUrl))" } else { $f.name }
  '| ' + $disp + ' | ' + ($cells -join ' | ') + ' |'
}
$policyTable = ($policyHeader,$policySep)+$policyRows -join "`n"


$readmeContent = Get-Content $readme -Raw
function Replace-Block($content,$marker,$new){
  $pattern = "(?s)<!-- BEGIN:$marker -->.*?<!-- END:$marker -->"
  if($content -notmatch $pattern){ return $content }
  return [regex]::Replace($content,$pattern,"<!-- BEGIN:$marker -->`n$new`n<!-- END:$marker -->")
}

# FUTURE_NEAR table intentionally omitted if markers not present in README (section deprecated); horizon section removed
$readmeContent = Replace-Block $readmeContent 'FUTURE_NEAR' $nearTable
$readmeContent = Replace-Block $readmeContent 'FLATTENED_FEATURES' ($flatList.TrimEnd())

$readmeContent = Replace-Block $readmeContent 'POLICY_MATRIX' $policyTable


Set-Content -Path $readme -Value $readmeContent -Encoding UTF8
Write-Host 'Future roadmap sections refreshed.'