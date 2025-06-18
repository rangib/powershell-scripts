[CmdletBinding()]

#Requires -RunAsAdministrator
param(
    [string] $TargetFolder,
    [string] $SitecoreVersion,
    [string[]] $EnsembleHosts,
    [string] $SslCertPath,
    [string] $SslCertPassword,
    [bool] $Force = $false
)

$Global:ProgressPreference = 'SilentlyContinue'

class SolrEnsembleConfig
{
    [string] $SolrVersion;
    [string] $ZooKeeperVersion;
    [string] $NonSuckingServiceManagerVersion;

    SolrEnsembleConfig()
    {

    }

    SolrEnsembleConfig([string] $SolrVersion, [string] $ZooKeeperVersion, [string] $NonSuckingServiceManagerVersion)
    {
        $this.SolrVersion = $SolrVersion;
        $this.ZooKeeperVersion = $ZooKeeperVersion;
        $this.NonSuckingServiceManagerVersion = $NonSuckingServiceManagerVersion;
    }
}

$VersionDictionary = [System.Collections.Generic.Dictionary[[string],[SolrEnsembleConfig]]]::new()
$VersionDictionary["9.2"] = [SolrEnsembleConfig]::new("7.5.0", "3.4.11", "2.24");

function Download-Solr
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $SavePath
    )

    begin
    {
        $SrcFile = [string]::Format("solr-{0}.zip", $Config.SolrVersion)
        $SrcUrl = [string]::Format("https://archive.apache.org/dist/lucene/solr/{0}/{1}", $Config.SolrVersion, $SrcFile)
        $TempPath = Join-Path -Path $SavePath -ChildPath $SrcFile
    }

    process
    {
        if (Test-Path -Path $TempPath)
        {
            Remove-Item -Path $TempPath | Out-Null
        }

        try
        {
            Write-Host "Downloading $($SrcUrl) ... " -NoNewline
            ([System.Net.WebClient]::new()).DownloadFile($SrcUrl, $TempPath) | Out-Null
            Write-Host "Done"
        }
        catch
        {
            $ResponseException = $_.Exception.Response.StatusCode.Value_
            Write-Host "Error"
            Write-Host -ForegroundColor Red "HTTP Error ($($ResponseException)) while attempting to download $($SrcUrl)"
        }

        if (!(Test-Path -Path $TempPath))
        {
            Write-Host "Cannot find $($TempPath)"
            Exit
        }

        return $TempPath
    }
}

function Download-ZooKeeper
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $SavePath
    )

    begin
    {
        $SrcFile = [string]::Format("zookeeper-{0}.tar.gz", $Config.ZooKeeperVersion)
        $SrcUrl = [string]::Format("https://archive.apache.org/dist/zookeeper/zookeeper-{0}/{1}", $Config.ZooKeeperVersion, $SrcFile)
        $TempPath = Join-Path -Path $SavePath -ChildPath $SrcFile
    }

    process
    {
        if (Test-Path -Path $TempPath)
        {
            Remove-Item -Path $TempPath | Out-Null
        }

        try
        {
            Write-Host "Downloading $($SrcUrl) ... " -NoNewline
            ([System.Net.WebClient]::new()).DownloadFile($SrcUrl, $TempPath) | Out-Null
            Write-Host "Done"
        }
        catch
        {
            $ResponseException = $_.Exception.Response.StatusCode.Value_
            Write-Host "Error"
            Write-Host -ForegroundColor Red "HTTP Error ($($ResponseException)) while attempting to download $($SrcUrl)"
        }

        if (!(Test-Path -Path $TempPath))
        {
            Write-Host "Cannot find $($TempPath)"
            Exit
        }

        return $TempPath
    }
}

function Download-Nssm
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $SavePath
    )

    begin
    {
        $SrcFile = [string]::Format("nssm-{0}.zip", $Config.NonSuckingServiceManagerVersion)
        $SrcUrl = [string]::Format("http://nssm.cc/release/{0}", $SrcFile)
        $TempPath = Join-Path -Path $SavePath -ChildPath $SrcFile
    }

    process
    {
        if (Test-Path -Path $TempPath)
        {
            Remove-Item -Path $TempPath | Out-Null
        }

        try
        {
            Write-Host "Downloading $($SrcUrl) ... " -NoNewline
            ([System.Net.WebClient]::new()).DownloadFile($SrcUrl, $TempPath) | Out-Null
            Write-Host "Done"
        }
        catch
        {
            $ResponseException = $_.Exception.Response.StatusCode.Value_
            Write-Host "Error"
            Write-Host -ForegroundColor Red "HTTP Error ($($ResponseException)) while attempting to download $($SrcUrl)"
        }

        if (!(Test-Path -Path $TempPath))
        {
            Write-Host "Cannot find $($TempPath)"
            Exit
        }

        return $TempPath
    }
}

function Install-Solr
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $InstallPath,
        [bool] $Force = $false
    )

    begin
    {
        $SrcAppName = "Solr"
        $SrcAppVersion = $Config.SolrVersion
        $SrcFilePath = Download-Solr -Config $Config -SavePath $env:TEMP
        $TmpFilePath = Join-Path -Path $env:TEMP -ChildPath ([Guid]::NewGuid().ToString())

        $TargetPath = Join-Path -Path $InstallPath -ChildPath ([string]::Format("{0}$([System.IO.Path]::DirectorySeparatorChar){1}", $SrcAppName.ToLower(), $SrcAppVersion))
    }

    process
    {
        $PathExists = Test-Path -Path $TargetPath

        if ($PathExists -and $Force)
        {
            Remove-Item -Path $TargetPath -Recurse | Out-Null
        }
        elseif ($PathExists -and !$Force)
        {
            Write-Host "$($SrcAppName) version $($SrcAppVersion) found ($($TargetPath)) ... Skipping"
            Return
        }
        
        try
        {
            Write-Host "Extracing $($SrcFilePath) ... " -NoNewline
            Expand-Archive -Path $SrcFilePath -DestinationPath $TmpFilePath -Force | Out-Null
            Write-Host "Done"
        }
        catch
        {
            Write-Host "Error"
            Exit
        }

        New-Item -Path $TargetPath -ItemType Directory | Out-Null
        Get-ChildItem -Path $TmpFilePath | Select-Object -First 1 | Get-ChildItem | Copy-Item -Destination $TargetPath -Force -Recurse | Out-Null

        return $TargetPath
    }
}

function Install-ZooKeeper
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $InstallPath,
        [bool] $Force = $false
    )

    begin
    {
        $SrcAppName = "ZooKeeper"
        $SrcAppVersion = $Config.ZooKeeperVersion
        $SrcFilePath = Download-Solr -Config $Config -SavePath $env:TEMP
        $TmpFilePath = Join-Path -Path $env:TEMP -ChildPath ([Guid]::NewGuid().ToString())

        $TargetPath = Join-Path -Path $InstallPath -ChildPath ([string]::Format("{0}$([System.IO.Path]::DirectorySeparatorChar){1}", $SrcAppName.ToLower(), $SrcAppVersion))
    }

    process
    {
        $PathExists = Test-Path -Path $TargetPath

        if ($PathExists -and $Force)
        {
            Remove-Item -Path $TargetPath -Recurse | Out-Null
        }
        elseif ($PathExists -and !$Force)
        {
            Write-Host "$($SrcAppName) version $($SrcAppVersion) found ($($TargetPath)) ... Skipping"
            Return
        }
        
        try
        {
            Write-Host "Extracing $($SrcFilePath) ... " -NoNewline
            Expand-Archive -Path $SrcFilePath -DestinationPath $TmpFilePath -Force | Out-Null
            Write-Host "Done"
        }
        catch
        {
            Write-Host "Error"
            Exit
        }

        New-Item -Path $TargetPath -ItemType Directory | Out-Null
        Get-ChildItem -Path $TmpFilePath | Select-Object -First 1 | Get-ChildItem | Copy-Item -Destination $TargetPath -Force -Recurse | Out-Null

        return $TargetPath
    }
}

function Install-Nssm
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $InstallPath,
        [bool] $Force = $false
    )

    begin
    {
        $SrcAppName = "NSSM"
        $SrcAppVersion = $Config.NonSuckingServiceManagerVersion
        $SrcFilePath = Download-Solr -Config $Config -SavePath $env:TEMP
        $TmpFilePath = Join-Path -Path $env:TEMP -ChildPath ([Guid]::NewGuid().ToString())

        $TargetPath = Join-Path -Path $InstallPath -ChildPath ([string]::Format("{0}$([System.IO.Path]::DirectorySeparatorChar){1}", $SrcAppName.ToLower(), $SrcAppVersion))
    }

    process
    {
        $PathExists = Test-Path -Path $TargetPath

        if ($PathExists -and $Force)
        {
            Remove-Item -Path $TargetPath -Recurse | Out-Null
        }
        elseif ($PathExists -and !$Force)
        {
            Write-Host "$($SrcAppName) version $($SrcAppVersion) found ($($TargetPath)) ... Skipping"
            Return
        }
        
        try
        {
            Write-Host "Extracing $($SrcFilePath) ... " -NoNewline
            Expand-Archive -Path $SrcFilePath -DestinationPath $TmpFilePath -Force | Out-Null
            Write-Host "Done"
        }
        catch
        {
            Write-Host "Error"
            Exit
        }

        New-Item -Path $TargetPath -ItemType Directory | Out-Null
        Get-ChildItem -Path $TmpFilePath | Select-Object -First 1 | Get-ChildItem | Copy-Item -Destination $TargetPath -Force -Recurse | Out-Null

        return $TargetPath
    }
}

function Setup-Solr
{
    param(
        [SolrEnsembleConfig] $Config,
        [string] $InstallPath,
        [string] $SslCertPath,
        [string] $SslCertPassword,
        [bool] $Force
    )

    begin
    {
        $TargetInstallPath = Install-Solr -Config $Config -InstallPath $InstallPath -Force $Force
        $ConfigFile = "solr.in.cmd"
        $ConfigFilePath = (Get-ChildItem -Path $TargetInstallPath -Filter $ConfigFile -Recurse | Select-Object -First 1).FullName
    }

    process
    {
        
    }
}

if ($VersionDictionary.ContainsKey($SitecoreVersion))
{
    Setup-Solr -Config $VersionDictionary[$SitecoreVersion] -InstallPath $TargetFolder -SslCertPath $SslCertPath -SslCertPassword $SslCertPassword -Force $Force
}