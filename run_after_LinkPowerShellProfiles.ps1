$basePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'

Get-Item $Home/.config/powershell/*profile.ps1 | ForEach-Object {
  $linkPath = Join-Path $basePath $_.Name
  if ((Get-Item $linkPath -erroraction silentlycontinue).linktype -ne 'HardLink') {
    Write-Host "Removing existing profile $linkPath to link to chezmoi profile. Confirm or cancel and move it."
    Remove-Item $linkPath -Confirm:$true
    New-Item -ItemType HardLink -Path $linkPath -Target $_.FullName
  }
}

