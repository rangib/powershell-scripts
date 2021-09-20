[CmdletBinding()]
param(
    #[Parameter(Mandatory=$true)]
    [string]$VirtualMachinesPath = "C:\Virtual Machines",
    [ValidateSet('List','Backup')]
    [string]$Command = 'List'
)

$ErrorActionPreference = 'silentlycontinue'

$VirtualMachines = [System.Collections.ArrayList]::new()

if ($VirtualMachinesPath)
{
    Get-ChildItem -Path $VirtualMachinesPath -Recurse -File -Filter "*.vmx" | Where-Object { $_.Extension -eq '.vmx' } | %{
        
        $VirtualMachineConfig = Get-Content -Path $_.FullName | ConvertFrom-StringData

        $VirtualMachines.Add(@{
            Name = $VirtualMachineConfig.displayName;
            Folder = [System.IO.Directory]::GetParent($_.FullName)
        }) | Out-Null

    }
}

if ($VirtualMachines.Count -le 0)
{
    Write-Output "No virtual machines found at the specified path"
    Exit
}
