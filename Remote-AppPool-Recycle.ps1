param(
    [Parameter(Mandatory=$true)]
    [string] $site = "killkentico.coateshire.devqa.switchit.com",
    [Parameter(Mandatory=$true)]
    [string] $server = "revan.switchit.local"
)

$cred = Get-Credential "switchit.local\Administrator"
$dc = New-PSSession -ComputerName $server -Credential $cred
Invoke-Command -Session $dc -ScriptBlock {
    param($site)
    & $env:windir\system32\inetsrv\appcmd.exe recycle apppool /apppool.name:$site
} -ArgumentList $site