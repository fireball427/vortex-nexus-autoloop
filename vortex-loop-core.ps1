function ConvertTo-NormalizedModName([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
  $value = $Name.ToLowerInvariant()
  $value = $value -replace '\s+-\s+(at\s+)?cyberpunk\s+2077\s+nexus.*$', ''
  $value = $value -replace '\s+-\s+opera$', ''
  $value = $value -replace '[^\p{L}\p{Nd}]+', ' '
  return (($value -replace '\s+', ' ').Trim())
}

function Test-TitleContainsModName([string]$ModName, [string]$PageTitle) {
  $mod = ConvertTo-NormalizedModName $ModName
  $page = ConvertTo-NormalizedModName $PageTitle
  if (!$mod -or !$page) { return $false }
  return $page.Contains($mod)
}

function Test-NextModChanged([string]$PreviousMod, [string]$CurrentMod) {
  $previous = ConvertTo-NormalizedModName $PreviousMod
  $current = ConvertTo-NormalizedModName $CurrentMod
  if (!$previous -or !$current) { return $false }
  return $previous -ne $current
}

function Get-ManualStartClickCount([int]$Attempt) {
  if ($Attempt -eq 1) { return 3 }
  return 1
}

function Get-HandoffRetryAction([bool]$NamesMatch, [bool]$LinkVisible, [int]$LinkAttempts, [bool]$VortexTried) {
  if (-not $NamesMatch) { return 'stop-name-mismatch' }
  if ($LinkVisible -and $LinkAttempts -lt 3 -and -not $VortexTried) { return 'click-start-download-manually' }
  if (-not $VortexTried) { return 'retry-vortex-manual' }
  return 'stop'
}

function Test-ShouldRetryManual([string]$ExpectedMod, [string]$VortexMod, [string]$BrowserTitle, [bool]$OpenVortexVisible) {
  if ($OpenVortexVisible) { return $false }
  $expected = ConvertTo-NormalizedModName $ExpectedMod
  $vortex = ConvertTo-NormalizedModName $VortexMod
  if (!$expected -or !$vortex -or $expected -ne $vortex) { return $false }
  return (Test-TitleContainsModName $ExpectedMod $BrowserTitle)
}
