$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vortex-loop-core.ps1')
$parseTokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'vortex-nexus-loop.ps1'), [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Main script failed to parse' }
$cycle = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-OneCycle' }, $true)
if (-not $cycle) { throw 'Invoke-OneCycle not found' }
. ([scriptblock]::Create($cycle.Extent.Text))

$TimeoutSeconds = 30
$script:statesRead = 0
$script:clicks = [System.Collections.Generic.List[string]]::new()
$script:waits = 0
$script:advance = $true
function Get-VortexState {
  $script:statesRead++
  if ($script:statesRead -eq 1) { return [pscustomobject]@{ ManualButton = 'vortex-button'; ModName = 'Example Mod A'; Counter = '12/100' } }
  return [pscustomobject]@{ ManualButton = $null; ModName = ''; Counter = '' }
}
function Invoke-UiButton($button, [string]$label) { $script:clicks.Add($label) }
function Wait-ForBrowserMod([string]$mod, [int]$seconds) { return [pscustomobject]@{ Title = 'Example Mod A at Nexus'; SlowButton = 'slow-button' } }
function Wait-ForHandoff([string]$mod, [string]$counter, [int]$seconds) { return [pscustomobject]@{ Kind = 'timeout'; Value = $null } }
function Find-OpenVortexButton { return $null }
function Get-BrowserState { return [pscustomobject]@{ Title = 'Unrelated previous tab at Nexus'; Elements = @(); WindowHandle = [IntPtr]::Zero } }
function Assert-NoInterruption($browser) { }
function Find-Link($elements, [string]$label) { return $null }
function Invoke-BrowserManualMouseClick($link, [IntPtr]$handle) { throw 'FAIL: clicked an unrelated browser tab' }
function Wait-ForNextMod([string]$mod, [string]$counter, [int]$seconds) {
  $script:waits++
  if ($script:advance) { return [pscustomobject]@{ ManualButton = 'next'; ModName = 'Example Mod B'; Counter = '13/100' } }
  return [pscustomobject]@{ ManualButton = $null; ModName = ''; Counter = '' }
}
$result = Invoke-OneCycle
if (-not $result -or $script:waits -ne 1 -or $script:clicks.Count -ne 2) { throw 'FAIL: changed tab did not wait safely for verified advancement' }
Write-Output 'PASS: changed tab waits for verified Vortex advancement without extra clicks'
$script:statesRead = 0; $script:clicks.Clear(); $script:waits = 0; $script:advance = $false
$stopped = $false
try { [void](Invoke-OneCycle) } catch { $stopped = $_.Exception.Message -match 'Handoff unverified' }
if (-not $stopped -or $script:waits -ne 1 -or $script:clicks.Count -ne 2) { throw 'FAIL: unverified transition did not stop safely' }
Write-Output 'PASS: changed tab without verified advancement stops without extra clicks'
