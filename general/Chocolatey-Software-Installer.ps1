#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string] $ConfigurationFile
)

if (!(Test-Path $ConfigurationFile)) {
    throw 'Chocolatey software configuration file not found'
}

$Chocolatey = (Get-Command -Name "choco.exe").Path

if (!(Test-Path $Chocolatey)) {
    throw 'Chocolatey does not appear to be installed'
}

$ChocolateyConfig = Get-Content -Path $ConfigurationFile -Encoding UTF8 | ConvertFrom-Json

if ($ChocolateyConfig.packages) {

    for ($i = 0; $i -lt $ChocolateyConfig.packages.length; $i++) {

        $Section = $ChocolateyConfig.packages[$i]
        Write-Host "Processing package category: $($Section.category)" -ForegroundColor Green

        for ($j = 0; $j -lt $Section.ids.length; $j++) {

            Write-Host "Starting installation of: $($Section.ids[$j])" -ForegroundColor Yellow

            $psi = New-Object System.Diagnostics.ProcessStartInfo -Prop @{
                RedirectStandardError = $false
                RedirectStandardOutput = $false
                UseShellExecute = $false
                CreateNoWindow = $false
                FileName = $Chocolatey
                Arguments = "install -y $($Section.ids[$j])"
                WindowStyle = "Hidden"
            }

            $p = New-Object System.Diagnostics.Process -Prop @{
                StartInfo = $psi
            }

            $p.Start() | Out-Null
            $p.WaitForExit()

        }
    }

}