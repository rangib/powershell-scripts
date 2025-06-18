[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SitecoreVersion,
    [Parameter(Mandatory=$true)]
    [string]$IndexPrefix,
    [Parameter(Mandatory=$true)]
    [string]$ZooKeeperServers,
    [string]$SolrArchivePath
)

$Global:ProgressPreference = 'SilentlyContinue'

class XmlUtil
{
    static [void]SetXmlElementValue([string]$XmlFilePath, [string]$XPath, [string]$ElementValue)
    {
        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $XmlNode = $XmlDoc.SelectSingleNode($XPath)
            $XmlNode.InnerText = $ElementValue

            $XmlDoc.Save($XmlFilePath)
        }
    }

    static [string]GetXmlElementValue([string]$XmlFilePath, [string]$XPath)
    {
        $Result = [string]::Empty

        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $XmlNode = $XmlDoc.SelectSingleNode($XPath)

            $Result = $XmlNode.InnerText

            $XmlNode = $null
            $XmlDoc = $null
        }

        return $Result
    }

    static [void]SetXmlAttributeValue([string]$XmlFilePath, [string]$XPath, [string]$Attribute, [string]$AttributeValue)
    {
        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $XmlNode = $XmlDoc.SelectSingleNode($XPath)
            $XmlNode.SetAttribute($Attribute, $AttributeValue)

            $XmlDoc.Save($XmlFilePath)
        }
    }

    static [string]GetXmlAttributeValue([string]$XmlFilePath, [string]$XPath, [string]$Attribute)
    {
        $Result = [string]::Empty

        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $XmlNode = $XmlDoc.SelectSingleNode($XPath)

            $Result = $XmlNode.GetAttribute($Attribute)

            $XmlNode = $null
            $XmlDoc = $null
        }

        return $Result
    }

    static [void]NewXmlElementAndAttribute([string]$XmlFilePath, [string]$XPath, [string]$ElementName, [string]$Attribute, [string]$AttributeValue)
    {
        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $ChildNode = $XmlDoc.CreateElement($ElementName)
            $ChildNode.SetAttribute($Attribute, $AttributeValue)

            $ParentNode = $XmlDoc.SelectSingleNode($XPath)

            [void]$ParentNode.AppendChild($ChildNode)

            $XmlDoc.Save($XmlFilePath)
        }
    }
}

class Sitecore
{
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $SitecoreSolrVersionMap = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $SitecoreSolrIndexMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $XconnectSolrIndexMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.Generic.Dictionary[[string],[string]]]]] $IndexAliasMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.Generic.Dictionary[[string],[string]]]]]::new()

    Sitecore()
    {
        $this.PopulateSitecoreSolrVersionMap()
        $this.PopulateSitecoreSolrIndexMap()
        $this.PopulateXconnectSolrIndexMap()
        $this.PopulateIndexAliasMap()
    }

    hidden [void] PopulateSitecoreSolrVersionMap()
    {
        $this.SitecoreSolrVersionMap.Add("9.2", "7.5.0")
    }

    hidden [void] PopulateSitecoreSolrIndexMap()
    {
        $this.SitecoreSolrIndexMap.Add("9.2", @("_core_index","_fxm_master_index","_fxm_web_index","_marketing_asset_index_master","_marketing_asset_index_web","_marketingdefinitions_master","_marketingdefinitions_web","_master_index","_suggested_test_index","_testing_index","_web_index"))
    }

    hidden [void] PopulateXconnectSolrIndexMap()
    {
        $this.XconnectSolrIndexMap.Add("9.2", @("_xdb", "_xdb_rebuild"))
    }

    hidden [void] PopulateIndexAliasMap()
    {
        $this.IndexAliasMap.Add("9.2", [System.Collections.Generic.Dictionary[[string],[string]]]::new())
        $this.IndexAliasMap["9.2"].Add("_xdb", "xdb")
        $this.IndexAliasMap["9.2"].Add("_xdb_rebuild", "xdb_rebuild")
    }

    [string] GetSolrVersion([string] $SitecoreVersion)
    {
        return $this.SitecoreSolrVersionMap[$SitecoreVersion]
    }

    [System.Collections.ArrayList] GetSitecoreSolrIndexArray([string] $SitecoreVersion)
    {
        return $this.SitecoreSolrIndexMap[$SitecoreVersion]
    }

    [System.Collections.ArrayList] GetXconnectSolrIndexArray([string] $SitecoreVersion)
    {
        return $this.XconnectSolrIndexMap[$SitecoreVersion]
    }

    [System.Collections.Generic.Dictionary[[string],[string]]] GetIndexAliases([string] $SitecoreVersion)
    {
        return $this.IndexAliasMap[$SitecoreVersion]
    }

    [void] PatchSitecoreIndexSolrConfig([string] $SitecoreVersion, [string] $CollectionFolderPath)
    {
        switch ($SitecoreVersion)
        {
            "9.2" {

                $XmlFilePath = (Get-ChildItem -Path $CollectionFolderPath -Filter "solrconfig.xml" | Select-Object -ExpandProperty FullName)

                $XPath = "//updateRequestProcessorChain"
                $Attribute = "default"
                $AttributeValue = "`${update.autoCreateFields:false}"

                [XmlUtil]::SetXmlAttributeValue($XmlFilePath, $XPath, $Attribute, $AttributeValue)
            }
        }
    }

    [void] PatchSitecoreIndexManagedSchema([string] $SitecoreVersion, [string] $CollectionFolderPath)
    {
        switch ($SitecoreVersion)
        {
            "9.2" {
                
                $XmlFilePath = (Get-ChildItem -Path $CollectionFolderPath -Filter "managed-schema" | Select-Object -ExpandProperty FullName)

                [XmlUtil]::SetXmlElementValue($XmlFilePath, "//uniqueKey", "_uniqueid")

                [XmlUtil]::NewXmlElementAndAttribute($XmlFilePath, "/schema", "field", "name", "_uniqueid")
                [XmlUtil]::SetXmlAttributeValue($XmlFilePath, "(//field[@name='_uniqueid'])[1]", "type", "string")
                [XmlUtil]::SetXmlAttributeValue($XmlFilePath, "(//field[@name='_uniqueid'])[1]", "indexed", "true")
                [XmlUtil]::SetXmlAttributeValue($XmlFilePath, "(//field[@name='_uniqueid'])[1]", "required", "true")
                [XmlUtil]::SetXmlAttributeValue($XmlFilePath, "(//field[@name='_uniqueid'])[1]", "stored", "true")

            }
        }
    }

    [void] PatchXconnectIndexSolrConfig([string] $SitecoreVersion, [string] $CollectionFolderPath)
    {
        switch ($SitecoreVersion)
        {
            "9.2" {

                $XmlFilePath = (Get-ChildItem -Path $CollectionFolderPath -Filter "solrconfig.xml" | Select-Object -ExpandProperty FullName)

                $XPath = "//updateRequestProcessorChain"
                $Attribute = "default"
                $AttributeValue = "`${update.autoCreateFields:false}"

                [XmlUtil]::SetXmlAttributeValue($XmlFilePath, $XPath, $Attribute, $AttributeValue)
            }
        }
    }
}

class Solr
{
    hidden [string] $SolrArchiveFormat = "solr-{0}.zip"
    hidden [string] $SolrArchiveUri = "https://archive.apache.org/dist/lucene/solr/{0}/{1}"

    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $SolrChecksumMap = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $SolrBasicConfigPath = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()

    Solr()
    {
        $this.PopulateSolrChecksumMap()
        $this.PopulateSolrBasicConfigPath()
    }

    hidden [void] PopulateSolrChecksumMap()
    {
        $this.SolrChecksumMap.Add("7.5.0", "085EB16912DD91B40DFFEC363554CB434DB6AFF928761A9C1B852A56172C0C9A1026A875A10C3D1C8DC6D992E29BC2B273E83EB07876E544542AB44CE91407F1")
    }

    hidden [void] PopulateSolrBasicConfigPath()
    {
        $this.SolrBasicConfigPath.Add("7.5.0", @("server","solr","configsets","_default", "conf"))
    }

    hidden [string] GetSolrArchiveUrl([string] $SolrVersion)
    {
        return [string]::Format($this.SolrArchiveUri, $SolrVersion, $this.GetSolrArchiveName($SolrVersion))
    }

    [string] GetBasicSolrConfigPath([string] $SolrVersion)
    {
        return ($this.SolrBasicConfigPath[$SolrVersion] -join [System.IO.Path]::DirectorySeparatorChar)
    }

    [string] GetSolrArchiveName([string] $SolrVersion)
    {
        return [string]::Format($this.SolrArchiveFormat, $SolrVersion)
    }

    [bool] DownloadSolrArchive([string] $SolrVersion, [string] $DownloadPath)
    {
        $RetVal = $true

        try
        {
            ([System.Net.WebClient]::new()).DownloadFile($this.GetSolrArchiveUrl($SolrVersion), $DownloadPath)
        }
        catch
        {
            $RetVal = $false
        }

        return $RetVal
    }

    [bool] IsSolrArchiveChecksumValid([string] $SolrVersion, [string] $SolrArchivePath)
    {
        return ($this.SolrChecksumMap[$SolrVersion] -eq (Get-FileHash -Path $SolrArchivePath -Algorithm SHA512).Hash)
    }

    [void] DecompressSolrArchive([string] $SolrArchivePath, [string] $Destination)
    {
        Expand-Archive -Path $SolrArchivePath -DestinationPath $Destination
    }

    [void] CreateCollectionFolder([string] $BaseConfigPath, [string] $SolrCollectionPath)
    {
        Copy-Item -Path $BaseConfigPath -Destination $SolrCollectionPath -Recurse
    }

    [void] UploadConfiguration([string] $SolrPath, [string] $ConfigName, [string] $ConfigPath, [string] $ZooKeeperServers)
    {
        $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $StartInfo.CreateNoWindow = $true
        $StartInfo.UseShellExecute = $false
        $StartInfo.RedirectStandardInput = $true
        $StartInfo.RedirectStandardError = $true
        $StartInfo.FileName = (Get-ChildItem -Path $SolrPath -Filter "solr.cmd" -Recurse | Select-Object -ExpandProperty FullName)
        $StartInfo.Arguments = [string]::Format("zk upconfig -n {0} -d {1} -z {2}", $ConfigName, $ConfigPath, $ZooKeeperServers)

        $Process = [System.Diagnostics.Process]::new()
        $Process.StartInfo = $StartInfo
        $Process.Start()
        $Process.WaitForExit()
    }
}

class SolrCollectionManager
{
    hidden [string] $SitecoreVersion
    hidden [string] $IndexPrefix
    hidden [string] $ZooKeeperServers
    hidden [string] $SolrArchivePath

    hidden [string] $WorkingDirectory
    hidden [string] $SolrWorkingDirectory
    hidden [string] $BaseConfigDirectory
    hidden [string] $CollectionWorkingDirectory

    hidden [string] $SolrVersion
    hidden [System.Collections.ArrayList] $SitecoreIndexes = [System.Collections.ArrayList]::new()
    hidden [System.Collections.ArrayList] $XconnectIndexes = [System.Collections.ArrayList]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $IndexAliases = [System.Collections.Generic.Dictionary[[string],[string]]]::new()

    hidden [Sitecore] $Sitecore = [Sitecore]::new()
    hidden [Solr] $Solr = [Solr]::new()

    SolrCollectionManager([string] $SitecoreVersion, [string] $IndexPrefix, [string] $ZooKeeperServers, [string] $SolrArchivePath)
    {
        $this.SitecoreVersion = $SitecoreVersion
        $this.IndexPrefix = $IndexPrefix
        $this.ZooKeeperServers = $ZooKeeperServers
        $this.SolrArchivePath = $SolrArchivePath

        $this.WorkingDirectory = $PSScriptRoot
        $this.SolrWorkingDirectory = [string]::Format("{0}{1}solr", $this.WorkingDirectory, [System.IO.Path]::DirectorySeparatorChar)
        $this.BaseConfigDirectory = [string]::Format("{0}{1}config", $this.WorkingDirectory, [System.IO.Path]::DirectorySeparatorChar)
        $this.CollectionWorkingDirectory = [string]::Format("{0}{1}collections", $this.WorkingDirectory, [System.IO.Path]::DirectorySeparatorChar)
    }

    [void] Execute()
    {
        $this.SolrVersion = $this.Sitecore.GetSolrVersion($this.SitecoreVersion)
        $this.SitecoreIndexes = $this.Sitecore.GetSitecoreSolrIndexArray($this.SitecoreVersion)
        $this.XconnectIndexes = $this.Sitecore.GetXconnectSolrIndexArray($this.SitecoreVersion)
        $this.IndexAliases = $this.Sitecore.GetIndexAliases($this.SitecoreVersion)

        if ([string]::IsNullOrEmpty($this.SolrArchivePath))
        {
            $this.SolrArchivePath = [string]::Format("{0}{1}{2}", $this.WorkingDirectory, [System.IO.Path]::PathSeparator, $this.Solr.GetSolrArchiveName($this.SolrVersion))
        }

        if (!(Test-Path -Path $this.SolrArchivePath))
        {
            $this.Solr.DownloadSolrArchive($this.SolrVersion, $this.SolrArchivePath)
        }

        if (Test-Path -Path $this.SolrArchivePath)
        {
            if ($this.Solr.IsSolrArchiveChecksumValid($this.SolrVersion, $this.SolrArchivePath))
            {
                if (Test-Path -Path $this.SolrWorkingDirectory)
                {
                    Remove-Item -Path $this.SolrWorkingDirectory -Recurse -Force
                }

                $this.Solr.DecompressSolrArchive($this.SolrArchivePath, $this.SolrWorkingDirectory)
            }
        }

        if (Test-Path -Path $this.SolrWorkingDirectory)
        {
            $ArchiveContent = Get-ChildItem -Path $this.SolrWorkingDirectory | Select-Object -First 1

            Copy-Item -Path ([System.IO.Path]::Combine($ArchiveContent.FullName, $this.Solr.GetBasicSolrConfigPath($this.SolrVersion))) -Destination $this.BaseConfigDirectory -Recurse
        }

        foreach ($SitecoreIndex in $this.SitecoreIndexes)
        {
            $CollectionName = [string]::Format("{0}{1}", $this.IndexPrefix, $SitecoreIndex)
            $CollectionFolder = [System.IO.Path]::Combine($this.CollectionWorkingDirectory, $CollectionName)

            $this.Solr.CreateCollectionFolder($this.BaseConfigDirectory, $CollectionFolder)

            $this.Sitecore.PatchSitecoreIndexSolrConfig($this.SitecoreVersion, $CollectionFolder)
            $this.Sitecore.PatchSitecoreIndexManagedSchema($this.SitecoreVersion, $CollectionFolder)

            $this.Solr.UploadConfiguration($this.SolrWorkingDirectory, $CollectionName, $CollectionFolder, $this.ZooKeeperServers)
        }

        foreach ($XconnectIndex in $this.XconnectIndexes)
        {
            $CollectionName = [string]::Format("{0}{1}", $this.IndexPrefix, $XconnectIndex)
            $CollectionFolder = [System.IO.Path]::Combine($this.CollectionWorkingDirectory, $CollectionName)

            $this.Solr.CreateCollectionFolder($this.BaseConfigDirectory, $CollectionFolder)

            $this.Sitecore.PatchXconnectIndexSolrConfig($this.SitecoreVersion, $CollectionFolder)
            
            $this.Solr.UploadConfiguration($this.SolrWorkingDirectory, $CollectionName, $CollectionFolder, $this.ZooKeeperServers)
        }
    }
}

$SolrCollectionManager = [SolrCollectionManager]::new($SitecoreVersion, $IndexPrefix, $ZooKeeperServers, $SolrArchivePath)
$SolrCollectionManager.Execute()