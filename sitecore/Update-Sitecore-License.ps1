param(
    [Parameter(Mandatory=$true)]
    [string] $LicenseFilePath,
    [Parameter(Mandatory=$true)]
    [string] $SitecorePath,
    [Parameter(Mandatory=$true)]
    [string] $XConnectPath
)

if ([string]::IsNullOrEmpty($LicenseFilePath)) {
    throw "You must specify the license file path"
    exit
}

if (-not (Test-Path $LicenseFilePath)) {
    throw "The license file path you specified doesn't exist"
    exit
}

if ([string]::IsNullOrEmpty($SitecorePath)) {
    throw "You must specify the path to Sitecore"
    exit
}

if (-not (Test-Path $SitecorePath)) {
    throw "The Sitecore path you specified doesn't exist"
    exit
}

if ([string]::IsNullOrEmpty($XConnectPath)) {
    throw "You must specify the path to Sitecore XConnect"
    exit
}

if (-not (Test-Path $XConnectPath)) {
    throw "The Sitecore XConnect path you specified doesn't exist"
    exit
}

Write-Host "Looking for Sitecore license file ... "

Get-ChildItem -LiteralPath $SitecorePath -Recurse -Filter "license.xml" | %{
    Write-Host "Found: $($_.FullName) ... " -NoNewline
    Copy-Item -Path $LicenseFilePath -Destination $_.FullName -Force -Confirm:$false | Out-Null
    Write-Host "Updated"
}

Write-Host "Looking for Sitecore XConnect license files ... "

Get-ChildItem -LiteralPath $XConnectPath -Recurse -Filter "license.xml" | %{
    Write-Host "Found: $($_.FullName) ... " -NoNewline
    Copy-Item -Path $LicenseFilePath -Destination $_.FullName -Force -Confirm:$false | Out-Null
    Write-Host "Updated"
}

Write-Host "License files are now updated. You will need to restart/reboot your computer."