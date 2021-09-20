[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SitecorePath
)

Enum FilterType
{
    None = 0
    CreationDate = 1
    FileExtension = 2
}

$oldestDate = (Get-Date).AddDays(-14)
$packageExclusions = @(".txt",".xml")

$folders = @(
    @{ Name = "Logs"; Path = "App_Data\logs"; FilterType = [FilterType]::CreationDate; FilterValue = $oldestDate; },
    @{ Name = "Packages"; Path = "App_Data\packages"; FilterType = [FilterType]::FileExtension; FilterValue = $packageExclusions; },
    @{ Name = "Additional Packages"; Path = "App_Data\packages"; FilterType = [FilterType]::FileExtension; FilterValue = $packageExclusions; },
    @{ Name = "Media Cache"; Path = "App_Data\MediaCache"; FilterType = [FilterType]::None; }
);

if (Test-Path $SitecorePath)
{
    foreach ($folder in $folders)
    {
        $files = @()
        $filePath = [System.IO.Path]::Combine($SitecorePath, $folder.Path)
        $filterValue = $folder.FilterValue;

        switch ($folder.FilterType)
        {
            ([FilterType]::CreationDate) {
                $files = Get-ChildItem -Path $filePath | Where-Object { $_.CreationTime -le $filterValue }
                break
            }

            ([FilterType]::FileExtension) {
                $files = Get-ChildItem -Path $filePath | Where-Object { !($filterValue -contains $_.Extension) }
                break
            }

            ([FilterType]::None) {
                $files = Get-ChildItem -Path $filePath -File
                break
            }
        }

        Write-Host -NoNewline "Removing files for $($folder.Name) .... "
        
        $files | %{ Remove-Item $_.FullName | Out-Null }

        Write-Host "Done"
    }
}