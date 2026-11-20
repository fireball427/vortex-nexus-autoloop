[CmdletBinding()]
param(
  [switch]$Once,
  [switch]$Run,
  [ValidateRange(5,300)][int]$TimeoutSeconds = 90,
  [ValidateSet('', 'chrome', 'opera')][string]$Browser = '',
  [switch]$SkipAfterSlowDownload
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vortex-loop-core.ps1')
. (Join-Path $PSScriptRoot 'vortex-mouse.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-AppRoot([string]$ProcessName) {
  $processes = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 })
  if ($processes.Count -eq 0) { throw "Can't find a visible $ProcessName window. Open Vortex and your default supported browser first." }
  if ($processes.Count -gt 1) { throw "Multiple visible $ProcessName processes found. Close extra browser windows and try again." }
  $process = $processes[0]
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

function Invoke-BrowserManualMouseClick($Link, [IntPtr]$BrowserHandle) {
  try {
    if (-not $Link -or -not $Link.Current.IsEnabled -or $Link.Current.IsOffscreen -or $Link.Current.Name.Trim() -ne 'Start download manually') { return $false }
    $rect = $Link.Current.BoundingRectangle
  } catch { return $false }
  if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) { return $false }
  $x = [int][Math]::Floor($rect.Left + $rect.Width / 2)
  $y = [int][Math]::Floor($rect.Top + $rect.Height / 2)
  Send-BackgroundMouseClick $BrowserHandle $x $y
  Write-Host 'Sent browser mouse click: Start download manually (handoff not yet verified)'
  return $true
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
    SkipButton = $(if ($SkipAfterSlowDownload -and $manual) {
      $skipButtons = @(foreach ($element in $elements) {
        try {
          $info = $element.Current
          if ($info.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $info.Name -in @('Skip mod', 'Skip mode') -and $info.IsEnabled -and -not $info.IsOffscreen) { $element }
        } catch {}
      })
      if ($skipButtons.Count -eq 1) { $skipButtons[0] }
    })
    ModName = $modName; Counter = [string]$counter
  }
}

function Get-DefaultSupportedBrowser {
  if ($Browser) { return $Browser }
  $key = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
  $choice = Get-ItemProperty -Path $key -Name ProgId -ErrorAction SilentlyContinue
  $detected = Get-SupportedBrowserFromProgId $choice.ProgId
  if ($detected) { return $detected }

  $candidates = @()
  foreach ($name in @('chrome', 'opera')) {
    $hasNexus = @(Get-Process -Name $name -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match '(?i)\bnexus\b' })
    if ($hasNexus.Count -gt 0) { $candidates += $name }
  }
  if ($candidates.Count -eq 1) { return $candidates[0] }

  throw "The default HTTPS browser is unsupported or unknown (ProgId: '$($choice.ProgId)'). Pass -Browser chrome or -Browser opera, or keep a Nexus tab active in one supported browser."
}

function Get-BrowserWindow([string]$ProcessName) {
  $desktop = [System.Windows.Automation.AutomationElement]::RootElement
  $topWindows = $desktop.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
  $windows = @(foreach ($window in $topWindows) {
    try {
      $owner = Get-Process -Id $window.Current.ProcessId -ErrorAction SilentlyContinue
      if ($owner -and $owner.ProcessName -eq $ProcessName -and $window.Current.ControlType.ProgrammaticName -eq 'ControlType.Window' -and -not $window.Current.IsOffscreen -and $window.Current.NativeWindowHandle -ne 0 -and $window.Current.Name) {
        [pscustomobject]@{ Title = [string]$window.Current.Name; Handle = [IntPtr]$window.Current.NativeWindowHandle; Root = $window }
      }
    } catch {}
  })
  if ($script:browserHandle -ne [IntPtr]::Zero) {
    $selected = @($windows | Where-Object { $_.Handle -eq $script:browserHandle }) | Select-Object -First 1
  } else {
    $selected = Get-PreferredBrowserWindow $windows
  }
  if (-not $selected) { throw "Cannot uniquely select an open $ProcessName window. Keep one Nexus page active in only one $ProcessName window, then retry." }
  $script:browserHandle = $selected.Handle
  return $selected
}

function Get-BrowserState {
  if ($script:enforceDefaultBrowser -and (Get-DefaultSupportedBrowser) -ne $script:browserName) { throw 'The default browser changed during the run; stopping.' }
  $app = Get-BrowserWindow $script:browserName
  $elements = @(Get-Descendants $app.Root)
  $names = @($elements | ForEach-Object { Get-ElementName $_ })
  return [pscustomobject]@{
    Root = $app.Root; Elements = $elements; WindowHandle = $app.Handle
    Title = $app.Title
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

  # The external-app confirmation may be a separate browser-owned top-level window.
  $desktop = [System.Windows.Automation.AutomationElement]::RootElement
  $topWindows = $desktop.FindAll([System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($window in $topWindows) {
    try {
      $owner = Get-Process -Id $window.Current.ProcessId -ErrorAction SilentlyContinue
      if (-not $owner -or $owner.ProcessName -ne $script:browserName) { continue }
      $button = Find-Button @(Get-Descendants $window) 'Open Vortex'
      if ($button) { return $button }
    } catch {}
  }
  return $null
}

function Wait-ForHandoff([string]$PreviousMod, [string]$PreviousCounter, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $state = Get-VortexState
    if ($state.ManualButton -and (Test-VerifiedAdvance $PreviousMod $PreviousCounter $state.ModName $state.Counter)) {
      return [pscustomobject]@{ Kind = 'advanced'; Value = $state }
    }
    $button = Find-OpenVortexButton
    if ($button) { return [pscustomobject]@{ Kind = 'prompt'; Value = $button } }
    Assert-NoInterruption (Get-BrowserState)
    Start-Sleep -Milliseconds 400
  }
  return [pscustomobject]@{ Kind = 'timeout'; Value = $null }
}

function Wait-ForNextMod([string]$PreviousMod, [string]$PreviousCounter, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $state = Get-VortexState
    if ($state.ManualButton -and (Test-VerifiedAdvance $PreviousMod $PreviousCounter $state.ModName $state.Counter)) {
      return $state
    }
    Start-Sleep -Milliseconds 500
  }
  return Get-VortexState
}

function Get-SlowDownloadCountdown($State) {
  return [string]($State.Names | Where-Object { $_ -match '^\s*Your download will start in\b' } | Select-Object -First 1)
}

function Assert-SameDownloadPage($State, $Original, [string]$ModName) {
  Assert-NoInterruption $State
  if ($State.WindowHandle -ne $Original.WindowHandle -or $State.Title -notmatch '(?i)\bnexus\b' -or
      -not (Test-TitleContainsModName $ModName $State.Title)) {
    throw "Browser left the verified Nexus page for '$ModName'; not skipping."
  }
}

function Invoke-SkipAfterSlowDownload($BrowserState, [string]$ModName, [string]$Counter) {
  Assert-SameDownloadPage $BrowserState $BrowserState $ModName
  $alreadyCounting = [bool](Get-SlowDownloadCountdown $BrowserState)
  try { Invoke-UiButton $BrowserState.SlowButton 'Slow download' }
  catch { Write-Warning $_.Exception.Message }

  $confirmed = $false
  # Verify that Opera accepted the action, not that the download finished.
  for ($i = 0; $i -lt 8; $i++) {
    $current = Get-BrowserState
    Assert-SameDownloadPage $current $BrowserState $ModName
    if (-not $alreadyCounting -and (Get-SlowDownloadCountdown $current)) { $confirmed = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $confirmed) {
    Write-Warning "Browser did not confirm Slow download for '$ModName'. Check the page; click Slow download yourself only if it hasn't started."
    if ((Read-Host 'Type yes once Nexus has accepted Slow download, or press Enter to stop') -ne 'yes') {
      throw 'Slow download was not confirmed; nothing was skipped.'
    }
    Assert-SameDownloadPage (Get-BrowserState) $BrowserState $ModName
  }

  $vortex = Get-VortexState
  if ($vortex.ModName -ne $ModName -or $vortex.Counter -ne $Counter) {
    throw 'The Vortex item changed before Skip mod; nothing was skipped.'
  }
  if (-not $vortex.ManualButton -or -not $vortex.SkipButton) {
    throw 'Cannot find a unique, visible Skip mod button for the current Vortex item.'
  }
  Invoke-UiButton $vortex.SkipButton 'Skip mod'
  $isLast = ($Counter -match '^\s*(\d+)\s*/\s*(\d+)\s*$') -and ([int]$Matches[1] -eq [int]$Matches[2])
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    $next = Get-VortexState
    if ($next.ManualButton -and (Test-VerifiedAdvance $ModName $Counter $next.ModName $next.Counter)) {
      Write-Host "Vortex queue advanced to [$($next.Counter)] '$($next.ModName)'; archive completion not checked."
      return $true
    }
    if ($isLast -and -not $next.ManualButton) {
      Start-Sleep -Milliseconds 500
      if (-not (Get-VortexState).ManualButton) {
        Write-Host 'Final queue dialog closed; archive completion not checked.'
        return $false
      }
    }
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Vortex queue advancement was not verified after Skip mod for '$ModName'; not retrying."
}

function Invoke-OneCycle {
  $vortex = Get-VortexState
  if (-not $vortex.ManualButton) {
    Write-Host 'No Vortex "Download manually" dialog is present; stopping without clicking anything else.' -ForegroundColor Yellow
    return $false
  }
  if (-not $vortex.ModName) { throw 'Vortex showed the manual-download button but its mod name could not be read; stopping safely.' }

  if ($vortex.Counter -notmatch '^\s*\d+\s*/\s*\d+\s*$') { throw 'Vortex queue counter could not be read; stopping before clicking.' }
  $currentMod = $vortex.ModName
  $currentCounter = $vortex.Counter
  if ($SkipAfterSlowDownload -and -not $vortex.SkipButton) {
    throw 'Cannot find a unique, visible Skip mod button for the current Vortex item.'
  }
  Write-Host "Vortex current item [$($vortex.Counter)]: $currentMod"
  Invoke-UiButton $vortex.ManualButton 'Download manually'

  $browser = Wait-ForBrowserMod $currentMod $TimeoutSeconds
  Write-Host "Verified same mod in browser: $($browser.Title)"
  if ($SkipAfterSlowDownload) { return (Invoke-SkipAfterSlowDownload $browser $currentMod $currentCounter) }
  Invoke-UiButton $browser.SlowButton 'Slow download'

  $result = Wait-ForHandoff $currentMod $currentCounter 8
  $linkAttempts = 0
  $vortexTried = $false
  $finalBrowserTried = $false
  while ($result.Kind -eq 'timeout') {
    $vortexCheck = Get-VortexState
    if ($vortexCheck.ManualButton -and (Test-VerifiedAdvance $currentMod $currentCounter $vortexCheck.ModName $vortexCheck.Counter)) {
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
        if (-not (Invoke-BrowserManualMouseClick $link $browserCheck.WindowHandle)) {
          Write-Host 'Browser link changed; checking for handoff before any more clicks.'
          break
        }
      }
    } elseif ($action -eq 'retry-vortex-manual') {
      $vortexTried = $true
      Invoke-UiButton $vortexCheck.ManualButton 'Download manually'
      $retryBrowser = Wait-ForBrowserMod $currentMod $TimeoutSeconds
      Invoke-UiButton $retryBrowser.SlowButton 'Slow download'
    } elseif ($action -eq 'retry-browser-after-vortex') {
      $finalBrowserTried = $true
      Write-Host 'Final browser manual-download retry after Vortex retry.' -ForegroundColor Yellow
      if (-not (Invoke-BrowserManualMouseClick $link $browserCheck.WindowHandle)) {
        Write-Host 'Browser link changed; checking for handoff.'
      }
    } else {
      throw "Handoff unverified for '$currentMod' ($action). No further retry; inspect Vortex and Opera."
    }
    $result = Wait-ForHandoff $currentMod $currentCounter 8
  }
  if ($result.Kind -eq 'prompt') {
    # The user requested Open Vortex; do not change the permanent permission checkbox.
    if ((Get-OpenVortexClickMethod $script:browserName) -eq 'mouse') {
      $button = $result.Value
      if (-not $button.Current.IsEnabled -or $button.Current.IsOffscreen -or $button.Current.Name -ne 'Open Vortex') { throw 'Chrome Open Vortex prompt changed; stopping.' }
      $rect = $button.Current.BoundingRectangle
      if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) { throw 'Chrome Open Vortex prompt has no usable bounds; stopping.' }
      $browser = Get-BrowserState
      Send-BackgroundMouseClick $browser.WindowHandle ([int][Math]::Floor($rect.Left + $rect.Width / 2)) ([int][Math]::Floor($rect.Top + $rect.Height / 2))
      Write-Host 'Sent browser mouse click: Open Vortex (handoff not yet verified)'
    } else {
      Invoke-UiButton $result.Value 'Open Vortex'
    }
    $next = Wait-ForNextMod $currentMod $currentCounter $TimeoutSeconds
  } else { $next = $result.Value }
  if (-not ($next.ManualButton -and (Test-VerifiedAdvance $currentMod $currentCounter $next.ModName $next.Counter))) {
    throw "Handoff unverified: Vortex did not advance from '$currentMod'. Stopping."
  }
  Write-Host "Verified Vortex advanced from '$currentMod' to [$($next.Counter)] '$($next.ModName)'." -ForegroundColor Green
  return $true
}

if ($Once -and $Run) {
  Write-Error 'Choose either -Once or -Run, not both.'
  exit 1
}

$completed = 0
while ($true) {
  try {
    $defaultChoice = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -Name ProgId -ErrorAction SilentlyContinue
    $script:enforceDefaultBrowser = (-not $Browser) -and [bool](Get-SupportedBrowserFromProgId $defaultChoice.ProgId)
    $script:browserName = Get-DefaultSupportedBrowser
    $script:browserHandle = [IntPtr]::Zero
    Write-Host "Using browser: $script:browserName"
    $initialVortex = Get-VortexState
    $initialBrowser = Get-BrowserState
    Write-Host "Vortex: $($initialVortex.ModName) [$($initialVortex.Counter)]"
    Write-Host "Browser: $($initialBrowser.Title)"
    if ($SkipAfterSlowDownload) { Write-Host "Vortex Skip mod available: $([bool]$initialVortex.SkipButton)" }
    if (-not $Once -and -not $Run) {
      Write-Host 'Inspection only; no clicks made. Use -Once for one item or -Run to continue until the Vortex manual-download dialog disappears.' -ForegroundColor Cyan
      exit 0
    }

    do {
      $didCycle = Invoke-OneCycle
      if (-not $didCycle) { break }
      $completed++
      if ($Once) { break }
    } while ($Run)

    if ($Run -and -not $SkipAfterSlowDownload -and -not $didCycle) {
      Start-Sleep -Seconds 3
      if ((Get-VortexState).ManualButton) { continue }
    }
    Write-Host "Stopped after $completed completed cycle(s)." -ForegroundColor Green
    break
  } catch {
    if (-not $Run -or $SkipAfterSlowDownload) {
      Write-Error $_
      exit 1
    }
    Write-Warning "$($_.Exception.Message) — restarting from scratch in 5s..."
    Start-Sleep -Seconds 5
  }
}
