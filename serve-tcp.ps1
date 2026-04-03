param(
  [int]$Port = 5500,
  [string]$Root = "c:\work\workspace"
)

& "$PSScriptRoot\serve.ps1" -Port $Port -Root $Root
