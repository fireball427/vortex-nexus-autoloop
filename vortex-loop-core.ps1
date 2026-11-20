function Get-PreferredBrowserWindow([object[]]$Windows) {
  $nexus = @($Windows | Where-Object { $_.Title -match '(?i)\bnexus\b' })
  if ($nexus.Count -eq 1) { return $nexus[0] }
  if ($nexus.Count -gt 1) { return $null }
  if ($Windows.Count -eq 1) { return $Windows[0] }
  return $null
}

function Get-OpenVortexClickMethod([string]$Browser) {
  if ($Browser -eq 'chrome') { return 'mouse' }
  return 'invoke'
}

function Get-SupportedBrowserFromProgId([string]$ProgId) {
  switch -Regex ($ProgId) {
    '^ChromeHTML$' { return 'chrome' }
    '^Opera( ?GX)?Stable$' { return 'opera' }
    default { return '' }
  }
}

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

function Test-VerifiedAdvance([string]$PreviousMod, [string]$PreviousCounter, [string]$CurrentMod, [string]$CurrentCounter) {
  if (-not (Test-NextModChanged $PreviousMod $CurrentMod)) { return $false }
  if ($CurrentMod.Trim() -match '^(?i:loading\s*\.{0,3}|free)$') { return $false }
  if ($PreviousCounter -notmatch '^\s*(\d+)\s*/\s*(\d+)\s*$') { return $false }
  $previousNumber = [int]$Matches[1]; $previousTotal = [int]$Matches[2]
  if ($CurrentCounter -notmatch '^\s*(\d+)\s*/\s*(\d+)\s*$') { return $false }
  $currentNumber = [int]$Matches[1]; $currentTotal = [int]$Matches[2]
  return ($previousTotal -eq $currentTotal -and $previousNumber -ge 1 -and $currentNumber -le $currentTotal -and $currentNumber -gt $previousNumber)
}

function Get-ManualStartClickCount([int]$Attempt) {
  if ($Attempt -eq 1) { return 3 }
  return 1
}

function Get-HandoffRetryAction([bool]$NamesMatch, [bool]$LinkVisible, [int]$LinkAttempts, [bool]$VortexTried, [bool]$FinalBrowserTried = $false) {
  if (-not $NamesMatch) { return 'stop-name-mismatch' }
  if ($LinkVisible -and $LinkAttempts -lt 3 -and -not $VortexTried) { return 'click-start-download-manually' }
  if (-not $VortexTried) { return 'retry-vortex-manual' }
  if ($LinkVisible -and -not $FinalBrowserTried) { return 'retry-browser-after-vortex' }
  return 'stop'
}

function Test-ShouldRetryManual([string]$ExpectedMod, [string]$VortexMod, [string]$BrowserTitle, [bool]$OpenVortexVisible) {
  if ($OpenVortexVisible) { return $false }
  $expected = ConvertTo-NormalizedModName $ExpectedMod
  $vortex = ConvertTo-NormalizedModName $VortexMod
  if (!$expected -or !$vortex -or $expected -ne $vortex) { return $false }
  return (Test-TitleContainsModName $ExpectedMod $BrowserTitle)
}
