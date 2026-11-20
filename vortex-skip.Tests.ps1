$ErrorActionPreference = 'Stop'
# Load definitions only; the tests must never start the real UI loop.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'vortex-nexus-loop.ps1'), [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors -join "`n") }
$functions = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
. ([scriptblock]::Create(($functions.Extent.Text -join "`n")))
. (Join-Path $PSScriptRoot 'vortex-loop-core.ps1')

function Get-VortexState {
  if ($script:clicks.Contains('Skip mod')) {
    if ($script:changedAfterSkip) { return [pscustomobject]@{ ManualButton = 'manual'; SkipButton = 'skip'; ModName = 'Next Mod'; Counter = '1/4' } }
    if ($script:counterOnly) { return [pscustomobject]@{ ManualButton = 'manual'; SkipButton = 'skip'; ModName = 'Test Mod'; Counter = '2/4' } }
    if ($script:loadingAfterSkip) { return [pscustomobject]@{ ManualButton = 'manual'; ModName = 'Loading...'; Counter = '2/4' } }
    if ($script:skipDisappeared) { return [pscustomobject]@{ ManualButton = 'manual'; ModName = 'Test Mod'; Counter = '1/4' } }
    if (-not $script:skipIgnored -or $script:manualSkipDone -or ($script:retryWorks -and $script:skipAttempts -ge 2)) {
      if ($script:finalItem) { return [pscustomobject]@{ ManualButton = $null; ModName = ''; Counter = '' } }
      return [pscustomobject]@{ ManualButton = 'manual'; ModName = 'Next Mod'; Counter = '2/4' }
    }
  }
  $name = if ($script:wrongMod -and $script:clicks.Contains('Slow download')) { 'Other Mod' } else { 'Test Mod' }
  $counter = if ($script:finalItem) { '4/4' } else { '1/4' }
  return [pscustomobject]@{ ManualButton = 'manual'; SkipButton = 'skip'; ModName = $name; Counter = $counter }
}
function Wait-ForBrowserMod { Get-BrowserState }
function Get-BrowserState {
  $clicked = $script:clicks.Count -gt 0 -and $script:clicks[$script:clicks.Count - 1] -eq 'Slow download'
  $started = ($clicked -and -not $script:silent) -or $script:manualConfirmed -or $script:stale
  $names = if ($script:interrupted -and $clicked) { @('Verify you are human') } elseif ($started) { @('Your download will start in 4 seconds') } else { @('Slow download') }
  return [pscustomobject]@{ SlowButton = 'slow'; Title = 'Test Mod at Nexus Mods'; Names = $names; WindowHandle = [IntPtr]1 }
}
function Invoke-UiButton($Button, $Label) {
  if (-not $Button) { throw 'Missing test button' }
  $script:clicks.Add($Label)
  if ($Label -eq 'Skip mod') { $script:skipAttempts++ }
}
function Read-Host($Prompt) {
  if ($Prompt -like '*Skip mod*') {
    $script:skipAsked = $true
    $script:manualSkipDone = $script:allowManualSkip
    if ($script:cancelSkip) { return 'q' }
    return ''
  }
  $script:asked = $true
  if ($script:allowManual) { $script:manualConfirmed = $true; return 'yes' }
  return ''
}
function Start-Sleep { }
function Assert-Clicks([string]$Expected) {
  $actual = $script:clicks -join ', '
  if ($Expected -ne $actual) { throw "Expected clicks [$Expected]; got [$actual]" }
}
function Reset-Test {
  $script:clicks = New-Object 'System.Collections.Generic.List[string]'
  $script:silent = $script:manualConfirmed = $script:allowManual = $script:asked = $script:wrongMod = $script:interrupted = $script:finalItem = $script:stale = $false
  $script:skipIgnored = $script:allowManualSkip = $script:manualSkipDone = $script:skipAsked = $script:cancelSkip = $script:changedAfterSkip = $script:skipDisappeared = $false
  $script:counterOnly = $script:loadingAfterSkip = $script:retryWorks = $false
  $script:skipAttempts = 0
}
function Assert-Failure([string]$Pattern) {
  try { $null = Invoke-OneCycle; throw 'Expected cycle to fail' }
  catch { if ($_.Exception.Message -notlike $Pattern) { throw } }
  Assert-Clicks 'Download manually, Slow download'
}

$SkipAfterSlowDownload = $true
$TimeoutSeconds = 5
Reset-Test
if (-not (Invoke-OneCycle)) { throw 'Expected a verified queue advance' }
Assert-Clicks 'Download manually, Slow download, Skip mod'
'PASS: click Skip mod as soon as the countdown appears'

Reset-Test
$script:silent = $script:allowManual = $true
if (-not (Invoke-OneCycle) -or -not $script:asked) { throw 'Expected manual fallback and queue advance' }
Assert-Clicks 'Download manually, Slow download, Skip mod'
'PASS: silent Opera click allows manual confirmation without resending a click'

Reset-Test
$script:silent = $true
Assert-Failure '*not confirmed*'
'PASS: no confirmation means no skip'

Reset-Test
$script:wrongMod = $true
Assert-Failure '*changed before Skip*'
'PASS: a changed Vortex item is never skipped'

Reset-Test
$script:interrupted = $true
Assert-Failure '*verification, login, or error*'
if ($script:asked) { throw 'Unexpected manual fallback on verification page' }
'PASS: verification page halts without skip or fallback'

Reset-Test
$script:stale = $true
Assert-Failure '*not confirmed*'
'PASS: pre-existing countdown is not confirmation'

Reset-Test
$script:finalItem = $true
if (Invoke-OneCycle) { throw 'Expected terminal queue result' }
Assert-Clicks 'Download manually, Slow download, Skip mod'
'PASS: final dialog closing ends the loop without claiming download completion'

# Collapse the observation window; each mock returns a deterministic state.
$TimeoutSeconds = 0
$retryClicks = 'Download manually, Slow download, Skip mod, Download manually, Slow download, Skip mod'
Reset-Test
$script:skipIgnored = $script:retryWorks = $true
if (-not (Invoke-OneCycle) -or $script:skipAsked) { throw 'Expected an automatic retry of Download manually for the same mod' }
Assert-Clicks $retryClicks
'PASS: retries the same queued mod once and continues if the name changes'

Reset-Test
$script:skipIgnored = $script:allowManualSkip = $true
if (-not (Invoke-OneCycle) -or -not $script:skipAsked) { throw 'Expected manual Skip fallback and verified advance' }
Assert-Clicks $retryClicks
'PASS: a second ignored Vortex click prompts once and verifies manual advancement'

Reset-Test
$script:changedAfterSkip = $true
if (-not (Invoke-OneCycle) -or $script:skipAsked) { throw 'Expected a new mod name to continue even while the counter is unchanged' }
Assert-Clicks 'Download manually, Slow download, Skip mod'
'PASS: a different mod name advances without a counter change or manual prompt'

foreach ($scenario in @('cancel', 'unchanged', 'counter-only', 'loading', 'missing')) {
  Reset-Test
  $script:skipIgnored = $true
  $script:cancelSkip = $scenario -eq 'cancel'
  $script:counterOnly = $scenario -eq 'counter-only'
  $script:loadingAfterSkip = $scenario -eq 'loading'
  $script:skipDisappeared = $scenario -eq 'missing'
  $pattern = switch ($scenario) {
    'cancel' { '*cancelled*' }
    'unchanged' { '*advancement was not verified*' }
    default { '*not safe to request*' }
  }
  try { $null = Invoke-OneCycle; throw 'Expected cycle to stop' }
  catch { if ($_.Exception.Message -notlike $pattern) { throw } }
  $manualFallback = $scenario -in @('cancel', 'unchanged')
  if ([bool]$script:skipAsked -ne $manualFallback) { throw "Unexpected prompt state: $scenario" }
  $expectedClicks = if ($manualFallback) { $retryClicks } else { 'Download manually, Slow download, Skip mod' }
  Assert-Clicks $expectedClicks
  "PASS: bounded Skip recovery stops when state is $scenario"
}

# Check the production wait budgets without sleeping through them.
function Wait-ForSkipQueue([string]$ModName, [string]$Counter, [int]$Seconds) {
  $script:observedWait = $Seconds
  return [pscustomobject]@{ Kind = 'advanced' }
}
foreach ($limit in @(90, 5)) {
  Reset-Test
  $TimeoutSeconds = $limit
  $null = Invoke-OneCycle
  $expected = [Math]::Min(10, $limit)
  if ($script:observedWait -ne $expected) { throw "Expected $expected seconds before the manual prompt; got $script:observedWait" }
}
'PASS: automatic Skip verification waits up to 10 seconds, honoring a shorter timeout'
