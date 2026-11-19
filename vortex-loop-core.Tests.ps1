$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vortex-loop-core.ps1')
function Assert-Equal($actual, $expected, $label) {
  if ($actual -ne $expected) { throw "FAIL: $label (expected '$expected', got '$actual')" }
  Write-Output "PASS: $label"
}

Assert-Equal (Test-TitleContainsModName 'Kiroshi Optics Night Vision Mod' 'Kiroshi Optics Night Vision Mod at Cyberpunk 2077 Nexus - Mods and community - Opera') $true 'matching Vortex/browser mod names'
Assert-Equal (Test-TitleContainsModName 'Kiroshi Optics Night Vision Mod' 'Accidental fast travel bug fix at Cyberpunk 2077 Nexus - Opera') $false 'reject mismatched mod names'
Assert-Equal (Test-NextModChanged 'Kiroshi Optics Night Vision Mod' 'Kiroshi Optics Night Vision Mod') $false 'do not advance on identical names'
Assert-Equal (Test-NextModChanged 'Kiroshi Optics Night Vision Mod' 'Letter of the Law - Cyberpsycho Quest Fix') $true 'accept next item only when the name changes'
Assert-Equal (Get-HandoffRetryAction $true $true 0 $false) 'click-start-download-manually' 'prefer the browser manual-download link when names still match'
Assert-Equal (Get-HandoffRetryAction $true $true 2 $false) 'click-start-download-manually' 'allow a third browser attempt'
Assert-Equal (Get-HandoffRetryAction $true $true 3 $false) 'retry-vortex-manual' 'retry Vortex after three browser attempts'
Assert-Equal (Get-HandoffRetryAction $true $false 0 $false) 'retry-vortex-manual' 'retry Vortex when browser link is unavailable'
Assert-Equal (Get-HandoffRetryAction $true $true 3 $true) 'stop' 'bound retries'
Assert-Equal (Get-HandoffRetryAction $false $true 0 $false) 'stop-name-mismatch' 'do not retry when the mod names no longer match'
Assert-Equal (Test-ShouldRetryManual 'Letter of the Law' 'LETTER OF THE LAW' 'Letter Of The Law at Cyberpunk 2077 Nexus' $false) $true 'retry manual only when names still match and Open Vortex is absent'
Assert-Equal (Test-ShouldRetryManual 'Letter of the Law' 'Another Mod' 'Letter of the Law' $false) $false 'do not retry if Vortex advanced'
Assert-Equal (Test-ShouldRetryManual 'Letter of the Law' 'Letter of the Law' 'Letter of the Law' $true) $false 'do not retry if Open Vortex appeared'
Assert-Equal (Test-ShouldRetryManual 'Letter of the Law' 'Letter of the Law' 'Unrelated Nexus page' $false) $false 'do not retry if browser page is unrelated'
