[CmdletBinding()]
param(
    [string] $NewName
)

$domainJoined = (Get-WmiObject win32_computersystem).PartOfDomain

$userCredentials = Get-Credential -Message "$($env:USERDOMAIN) Admin Credentials"

if ($domainJoined) {
    Rename-Computer -NewName $NewName -ComputerName $env:COMPUTERNAME -DomainCredential $userCredentials -Restart
} else {
    Rename-Computer -NewName $NewName -ComputerName $env:COMPUTERNAME -LocalCredential $userCredentials -Restart
}