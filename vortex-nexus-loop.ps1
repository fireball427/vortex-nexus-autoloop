[CmdletBinding()]
param(
  [switch]$Once,
  [switch]$Run,
  [ValidateRange(5,300)][int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vortex-loop-core.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-AppRoot([string]$ProcessName) {
  $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
  if (-not $process) { throw "Can't find a visible $ProcessName window. Open Vortex and Opera first." }
  $element = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$process.MainWindowHandle)
  if (-not $element) { throw "Couldn't attach to the $ProcessName window." }
  return [pscustomobject]@{ Process = $process; Root = $element }
}

function Get-Descendants($Root) {
  return $Root.FindAll([System.Windows.Automation.TreeScope]::Subtree,
    [System.Windows.Automation.Condition]::TrueCondition)
}

function Get-ElementName($Element) {
  try { return [string]$Element.Current.Name } catch { return '' }
}

function Find-Button($Elements, [string]$Label) {
  foreach ($element in $Elements) {
    try {
      if ($element.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and
          $element.Current.Name -eq $Label -and $element.Current.IsEnabled) {
        return $element
      }
    } catch {}
  }
  return $null
}

function Find-Link($Elements, [string]$Label) {
  foreach ($element in $Elements) {
    try {
      if ($element.Current.ControlType.ProgrammaticName -eq 'ControlType.Hyperlink' -and $element.Current.Name.Trim() -eq $Label -and $element.Current.IsEnabled -and -not $element.Current.IsOffscreen) { return $element }
    } catch {}
  }
  return $null
}

function Invoke-UiButton($Button, [string]$Label) {
  if (-not $Button) { throw "Button not found: $Label" }
  try {
    $pattern = $Button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
  } catch {
    throw "Couldn't activate '$Label' through Windows UI Automation: $($_.Exception.Message)"
  }
  Write-Host "Clicked: $Label"
}

function Get-VortexState {
  $app = Get-AppRoot 'Vortex'
  $elements = @(Get-Descendants $app.Root)
  $manual = Find-Button $elements 'Download manually'
  $texts = @()
  foreach ($element in $elements) {
    try {
      if ($element.Current.ControlType.ProgrammaticName -eq 'ControlType.Text') {
        $texts += [string]$element.Current.Name
      }
    } catch {}
  }
  $counter = $texts | Where-Object { $_ -match '^\d+\s*/\s*\d+$' } | Select-Object -First 1
  $modName = ''
  $anchor = [Array]::IndexOf($texts, 'Download mod')
  if ($anchor -ge 0) {
    for ($i = $anchor + 1; $i -lt $texts.Count; $i++) {
      $candidate = ([string]$texts[$i]).Trim()
      if ($candidate -and $candidate -ne 'by' -and $candidate -notmatch '^\d+\s*/\s*\d+$') {
        $modName = $candidate
        break
      }
    }
  }
  return [pscustomobject]@{
    Root = $app.Root; Elements = $elements; ManualButton = $manual
    ModName = $modName; Counter = [string]$counter
  }
}

function Get-BrowserState {
  $app = Get-AppRoot 'opera'
  $elements = @(Get-Descendants $app.Root)
  $names = @($elements | ForEach-Object { Get-ElementName $_ })
  return [pscustomobject]@{
    Root = $app.Root; Elements = $elements
    Title = [string]$app.Process.MainWindowTitle
    SlowButton = Find-Button $elements 'Slow download'
    OpenButton = Find-Button $elements 'Open Vortex'
    Names = $names
  }
}

function Assert-NoInterruption($Browser) {
  $joined = ($Browser.Names -join "`n") + "`n" + $Browser.Title
  if ($joined -match '(?i)captcha|cloudflare|verify you are human|security check|access denied|sign in to continue|log in to continue|download unavailable') {
    throw "A verification, login, or error page appeared. Pausing without clicking it. Browser title: $($Browser.Title)"
  }
}

function Wait-ForBrowserMod([string]$ModName, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $browser = Get-BrowserState
    Assert-NoInterruption $browser
    if ((Test-TitleContainsModName $ModName $browser.Title) -and $browser.SlowButton) {
      return $browser
    }
    Start-Sleep -Milliseconds 500
  }
  $last = Get-BrowserState
  throw "Timed out waiting for a Nexus page matching '$ModName' with a Slow download button. Browser title: $($last.Title)"
}

function Find-OpenVortexButton {
  $browser = Get-BrowserState
  if ($browser.OpenButton) { return $browser.OpenButton }

  # The external-app confirmation may be a separate top-level window, not a child of Opera.
  $desktop = [System.Windows.Automation.AutomationElement]::RootElement
  $topWindows = $desktop.FindAll([System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($window in $topWindows) {
    try {
      $button = Find-Button @(Get-Descendants $window) 'Open Vortex'
      if ($button) { return $button }
    } catch {}
  }
  return $null
}

function Wait-ForHandoff([string]$PreviousMod, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $state = Get-VortexState
    if ($state.ManualButton -and (Test-NextModChanged $PreviousMod $state.ModName)) {
      return [pscustomobject]@{ Kind = 'advanced'; Value = $state }
    }
    $button = Find-OpenVortexButton
    if ($button) { return [pscustomobject]@{ Kind = 'prompt'; Value = $button } }
    Assert-NoInterruption (Get-BrowserState)
    Start-Sleep -Milliseconds 400
  }
  return [pscustomobject]@{ Kind = 'timeout'; Value = $null }
}

function Wait-ForNextMod([string]$PreviousMod, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $state = Get-VortexState
    if ($state.ManualButton -and $state.ModName -and (Test-NextModChanged $PreviousMod $state.ModName)) {
      return $state
    }
    Start-Sleep -Milliseconds 500
  }
  return Get-VortexState
}

function Invoke-OneCycle {
  $vortex = Get-VortexState
  if (-not $vortex.ManualButton) {
    Write-Host 'No Vortex "Download manually" dialog is present; stopping without clicking anything else.' -ForegroundColor Yellow
    return $false
  }
  if (-not $vortex.ModName) { throw 'Vortex showed the manual-download button but its mod name could not be read; stopping safely.' }

  $currentMod = $vortex.ModName
  Write-Host "Vortex current item [$($vortex.Counter)]: $currentMod"
  Invoke-UiButton $vortex.ManualButton 'Download manually'

  $browser = Wait-ForBrowserMod $currentMod $TimeoutSeconds
  Write-Host "Verified same mod in browser: $($browser.Title)"
  Invoke-UiButton $browser.SlowButton 'Slow download'

  $result = Wait-ForHandoff $currentMod 8
  $linkAttempts = 0
  $vortexTried = $false
  $finalBrowserTried = $false
  while ($result.Kind -eq 'timeout') {
    $vortexCheck = Get-VortexState
    if ($vortexCheck.ManualButton -and (Test-NextModChanged $currentMod $vortexCheck.ModName)) {
      $result = [pscustomobject]@{ Kind = 'advanced'; Value = $vortexCheck }
      break
    }
    $open = Find-OpenVortexButton
    if ($open) { $result = [pscustomobject]@{ Kind = 'prompt'; Value = $open }; break }
    $browserCheck = Get-BrowserState
    Assert-NoInterruption $browserCheck
    $link = Find-Link $browserCheck.Elements 'Start download manually'
    $namesMatch = Test-ShouldRetryManual $currentMod $vortexCheck.ModName $browserCheck.Title $false
    $action = Get-HandoffRetryAction $namesMatch ($null -ne $link) $linkAttempts $vortexTried $finalBrowserTried
    if ($action -eq 'click-start-download-manually') {
      $linkAttempts++
      $clickCount = Get-ManualStartClickCount $linkAttempts
      Write-Host "Browser fallback attempt $linkAttempts of 3 ($clickCount clicks)"
      for ($clickIndex = 1; $clickIndex -le $clickCount; $clickIndex++) {
        Invoke-UiButton $link 'Start download manually'
      }
    } elseif ($action -eq 'retry-vortex-manual') {
      $vortexTried = $true
      Invoke-UiButton $vortexCheck.ManualButton 'Download manually'
      $retryBrowser = Wait-ForBrowserMod $currentMod $TimeoutSeconds
      Invoke-UiButton $retryBrowser.SlowButton 'Slow download'
    } elseif ($action -eq 'retry-browser-after-vortex') {
      $finalBrowserTried = $true
      Write-Host 'Final browser manual-download retry after Vortex retry.' -ForegroundColor Yellow
      Invoke-UiButton $link 'Start download manually'
    } else {
      throw "Handoff unverified for '$currentMod' ($action). No further retry; inspect Vortex and Opera."
    }
    $result = Wait-ForHandoff $currentMod 8
  }
  if ($result.Kind -eq 'prompt') {
    # The user requested Open Vortex; do not change the permanent permission checkbox.
    Invoke-UiButton $result.Value 'Open Vortex'
    $next = Wait-ForNextMod $currentMod $TimeoutSeconds
  } else { $next = $result.Value }
  if (-not ($next.ManualButton -and $next.ModName -and (Test-NextModChanged $currentMod $next.ModName))) {
    throw "Handoff unverified: Vortex did not advance from '$currentMod'. Stopping."
  }
  Write-Host "Verified Vortex advanced from '$currentMod' to [$($next.Counter)] '$($next.ModName)'." -ForegroundColor Green
  return $true
}

try {
  $initialVortex = Get-VortexState
  $initialBrowser = Get-BrowserState
  Write-Host "Vortex: $($initialVortex.ModName) [$($initialVortex.Counter)]"
  Write-Host "Browser: $($initialBrowser.Title)"
  if (-not $Once -and -not $Run) {
    Write-Host 'Inspection only; no clicks made. Use -Once for one item or -Run to continue until the Vortex manual-download dialog disappears.' -ForegroundColor Cyan
    exit 0
  }
  if ($Once -and $Run) { throw 'Choose either -Once or -Run, not both.' }

  $completed = 0
  do {
    $didCycle = Invoke-OneCycle
    if (-not $didCycle) { break }
    $completed++
    if ($Once) { break }
  } while ($Run)
  Write-Host "Stopped after $completed completed cycle(s)." -ForegroundColor Green
} catch {
  Write-Error $_
  exit 1
}
