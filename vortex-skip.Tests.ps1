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
    if ($script:finalItem) { return [pscustomobject]@{ ManualButton = $null; ModName = ''; Counter = '' } }
    return [pscustomobject]@{ ManualButton = 'manual'; ModName = 'Next Mod'; Counter = '2/4' }
  }
  $name = if ($script:wrongMod -and $script:clicks.Contains('Slow download')) { 'Other Mod' } else { 'Test Mod' }
  $counter = if ($script:finalItem) { '4/4' } else { '1/4' }
  return [pscustomobject]@{ ManualButton = 'manual'; SkipButton = 'skip'; ModName = $name; Counter = $counter }
}
function Wait-ForBrowserMod { Get-BrowserState }
function Get-BrowserState {
  $clicked = $script:clicks.Contains('Slow download')
  $started = ($clicked -and -not $script:silent) -or $script:manualConfirmed -or $script:stale
  $names = if ($script:interrupted -and $clicked) { @('Verify you are human') } elseif ($started) { @('Your download will start in 4 seconds') } else { @('Slow download') }
  return [pscustomobject]@{ SlowButton = 'slow'; Title = 'Test Mod at Nexus Mods'; Names = $names; WindowHandle = [IntPtr]1 }
}
function Invoke-UiButton($Button, $Label) {
  if (-not $Button) { throw 'Missing test button' }
  $script:clicks.Add($Label)
}
function Read-Host($Prompt) {
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
