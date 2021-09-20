[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$AccountName,
    [Parameter(Mandatory=$true)]
    [string]$DeploymentUid,
    [Parameter(Mandatory=$true)]
    [string]$IndexPrefix,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password,
    [Parameter(Mandatory=$true)]
    [string]$SitecoreVersion,
    [Parameter(Mandatory=$true)]
    [ValidateSet("XP","SXA","XConnect","Commerce")]
    [string]$InstallMode = "XP",
    [string]$SolrUsername = "",
    [string]$SolrPassword = "",
    [bool]$Clean = $false,
    [bool]$DryRun = $true
)

$Global:ProgressPreference = 'SilentlyContinue'

enum CollectionStatus
{
    ConfigCreated
    ArchiveCreated
    UploadFailed
    UploadSuccess
    CollectionSkipped
    CollectionCreated
}

class Constants
{
    hidden static [Constants] $Instance

    static [Constants] GetInstance()
    {
        if ($null -eq [Constants]::Instance)
        {
            [Constants]::Instance = [Constants]::new()
        }

        return [Constants]::Instance
    }

    hidden Constants()
    {
        $this.SleepSeconds = 5
        $this.RetryMaxCount = 3
        $this.WorkingDir = $PSScriptRoot
        $this.SolrWorkingDir = Join-Path -Path $this.WorkingDir -ChildPath "solr"
        $this.IndexesWorkingDir = Join-Path -Path $this.WorkingDir -ChildPath "indexes"
        $this.ConfigSetUploadDir = Join-Path -Path $this.WorkingDir -ChildPath "upload"
        $this.ConfigSetWorkingDir = Join-Path -Path $this.WorkingDir -ChildPath "configs"
    }

    [int]$SleepSeconds
    [int]$RetryMaxCount
    [string]$WorkingDir
    [string]$SolrWorkingDir
    [string]$IndexesWorkingDir
    [string]$ConfigSetUploadDir
    [string]$ConfigSetWorkingDir
}

class XmlUtil
{
    static [string] GetXmlElementValue([string] $XmlFilePath, [string] $XPath)
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

    static [void] SetXmlElementValue([string] $XmlFilePath, [string] $XPath, [string] $ElementValue)
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

    static [void] DeleteXmlElementValue([string] $XmlFilePath, [string] $XPath)
    {
        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $XmlNode = $XmlDoc.SelectSingleNode($XPath)
            $XmlNode.ParentNode.RemoveChild($XmlNode)

            $XmlDoc.Save($XmlFilePath)
        }
    }

    static [void] SetXmlAttributeValue([string] $XmlFilePath, [string] $XPath, [string] $Attribute, [string] $AttributeValue)
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

    static [string] GetXmlAttributeValue([string] $XmlFilePath, [string] $XPath, [string] $Attribute)
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

    static [void] NewXmlElementAndAttribute([string] $XmlFilePath, [string] $XPath, [string] $ElementName, [string] $Attribute, [string] $AttributeValue)
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

    static [void] NewXmlElementAndAttributeBefore([string] $XmlFilePath, [string] $XPath, [string] $ElementName, [string] $Attribute, [string] $AttributeValue)
    {
        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $Node = $XmlDoc.CreateElement($ElementName)
            $Node.SetAttribute($Attribute, $AttributeValue)

            $RootNode = $XmlDoc.DocumentElement
            $SiblingNode = $XmlDoc.SelectSingleNode($XPath)

            [void]$RootNode.InsertBefore($Node, $SiblingNode)

            $XmlDoc.Save($XmlFilePath)
        }
    }

    static [void] NewXmlElementAndAttributeAfter([string] $XmlFilePath, [string] $XPath, [string] $ElementName, [string] $Attribute, [string] $AttributeValue)
    {
        if (Test-Path -Path $XmlFilePath)
        {
            $XmlDoc = [System.Xml.XmlDocument]::new()
            $XmlDoc.Load($XmlFilePath)

            $Node = $XmlDoc.CreateElement($ElementName)
            $Node.SetAttribute($Attribute, $AttributeValue)

            $RootNode = $XmlDoc.DocumentElement
            $SiblingNode = $XmlDoc.SelectSingleNode($XPath)

            [void]$RootNode.InsertAfter($Node, $SiblingNode)

            $XmlDoc.Save($XmlFilePath)
        }
    }
}

class SolrConfig
{
    [System.Collections.Generic.Dictionary[[string], [System.Collections.Generic.List[ConfigSchema]]]] $Configs = [System.Collections.Generic.Dictionary[[string], [System.Collections.Generic.List[ConfigSchema]]]]::new()

    SolrConfig()
    {
        $this.Configs.Add("9.2", [System.Collections.Generic.List[ConfigSchema]]::new())

        $this.CreateXpDefaultConfigs("9.2")
        $this.CreateXconnectDefaultConfigs("9.2")
        $this.CreateCommerceDefaultConfigs("9.2")
        $this.CreateSxaDefaultConfigs("9.2")
    }

    hidden [void] CreateXpDefaultConfigs([string] $SitecoreVersion)
    {
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_core_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_fxm_master_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_fxm_web_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_marketing_asset_index_master", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_marketing_asset_index_web", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_marketingdefinitions_master", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_marketingdefinitions_web", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_master_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_suggested_test_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_testing_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_web_index", "false"))
    }

    hidden [void] CreateXconnectDefaultConfigs([string] $SitecoreVersion)
    {
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_xdb", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_xdb_rebuild", "false"))
    }

    hidden [void] CreateCommerceDefaultConfigs([string] $SitecoreVersion)
    {
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_catalog_items_scope", "true"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_customers_scope", "true"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_orders_scope", "true"))
    }

    hidden [void] CreateSxaDefaultConfigs([string] $SitecoreVersion)
    {
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_sxa_master_index", "false"))
        $this.Configs[$SitecoreVersion].Add($this.CreateSolrConfig("_sxa_web_index", "false"))
    }

    hidden [ConfigSchema] CreateSolrConfig([string] $CollectionName, [string] $AutoCreateFieldsValue)
    {
        $ConfigField = [ConfigField]::new()
        $ConfigField.XPath = "//updateRequestProcessorChain"
        $ConfigField.Attribute = "default"
        $ConfigField.Value = "`${update.autoCreateFields:$($AutoCreateFieldsValue)}"

        $ConfigSchema = [ConfigSchema]::new()
        $ConfigSchema.Name = $CollectionName
        $ConfigSchema.Fields.Add($ConfigField)

        return $ConfigSchema
    }
}

class ManagedSchema
{
    [System.Collections.Generic.Dictionary[[string], [System.Collections.Generic.List[CollectionSchema]]]] $Collections = [System.Collections.Generic.Dictionary[[string], [System.Collections.Generic.List[CollectionSchema]]]]::new()

    ManagedSchema()
    {
        $this.Collections.Add("9.2", [System.Collections.Generic.List[CollectionSchema]]::new())

        $this.CreateXpDefaultManagedSchema()
		$this.CreateSxaManagedSchema()
        $this.CreateCatalogManagedSchema()
        $this.CreateCustomerManagedSchema()
        $this.CreateOrderManagedSchema()
    }

    hidden [void] CreateXpDefaultManagedSchema()
    {
        $this.Collections["9.2"].Add($this.CreateXpSchema("_core_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_fxm_master_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_fxm_web_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_marketing_asset_index_master"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_marketing_asset_index_web"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_marketingdefinitions_master"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_marketingdefinitions_web"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_master_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_suggested_test_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_testing_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_web_index"))
    }
	
    hidden [void] CreateSxaManagedSchema()
    {
        $this.Collections["9.2"].Add($this.CreateXpSchema("_sxa_master_index"))
        $this.Collections["9.2"].Add($this.CreateXpSchema("_sxa_web_index"))
    }

    hidden [CollectionSchema] CreateXpSchema([string] $Name)
    {
        $XpManagedSchema = [CollectionSchema]::new()

        $XpManagedSchema.Name = $Name
        $XpManagedSchema.Parent = "(//field[@name='_text_'])"
        $XpManagedSchema.UniqueKey = "_uniqueid"

        $XpManagedSchema.Fields.Add($this.Field("_uniqueid", "string", $true, $true, $true))

        return $XpManagedSchema
    }

    hidden [void] CreateCatalogManagedSchema()
    {
        $CatalogManagedSchema = [CollectionSchema]::new()
        $CatalogManagedSchema.Name = "_catalog_items_scope"
        $CatalogManagedSchema.Parent = "(//field[@name='_text_'])"
        $CatalogManagedSchema.UniqueKey = "sitecoreid"

        $CatalogManagedSchema.Fields.Add($this.Field("entityuniqueid", "string", $true, $true, $true))
        $CatalogManagedSchema.Fields.Add($this.Field("entityid", "string", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("entityversion", "pint", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("sitecoreid", "string", $true, $true, $true))

        $CatalogManagedSchema.Fields.Add($this.Field("displayname", "string", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("datecreated", "pdate", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("dateupdated", "pdate", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("artifactstoreid", "string", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("variantid", "string", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("variantdisplayname", "string", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("productid", "string", $true, $true, $false))
        $CatalogManagedSchema.Fields.Add($this.Field("name", "string", $true, $true, $false))

        $CatalogManagedSchema.Fields.Add($this.CopyField("displayname", "_text_"))
        $CatalogManagedSchema.Fields.Add($this.CopyField("variantid", "_text_"))
        $CatalogManagedSchema.Fields.Add($this.CopyField("variantdisplayname", "_text_"))
        $CatalogManagedSchema.Fields.Add($this.CopyField("productid", "_text_"))
        $CatalogManagedSchema.Fields.Add($this.CopyField("name", "_text_"))

        $this.Collections["9.2"].Add($CatalogManagedSchema)
    }

    hidden [void] CreateCustomerManagedSchema()
    {
        $CustomerManagedSchema = [CollectionSchema]::new()
        $CustomerManagedSchema.Name = "_customers_scope"
        $CustomerManagedSchema.Parent = "(//field[@name='_text_'])"
        $CustomerManagedSchema.UniqueKey = "entityid"

        $CustomerManagedSchema.Fields.Add($this.Field("entityuniqueid", "string", $true, $true, $true))
        $CustomerManagedSchema.Fields.Add($this.Field("entityid", "string", $true, $true, $true))
        $CustomerManagedSchema.Fields.Add($this.Field("entityversion", "pint", $true, $true, $false))

        $CustomerManagedSchema.Fields.Add($this.Field("username", "string", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("email", "string", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("status", "string", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("firstname", "string", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("lastname", "string", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("datecreated", "pdate", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("dateupdated", "pdate", $true, $true, $false))
        $CustomerManagedSchema.Fields.Add($this.Field("artifactstoreid", "string", $true, $true, $false))

        $CustomerManagedSchema.Fields.Add($this.CopyField("username", "_text_"))
        $CustomerManagedSchema.Fields.Add($this.CopyField("email", "_text_"))
        $CustomerManagedSchema.Fields.Add($this.CopyField("status", "_text_"))
        $CustomerManagedSchema.Fields.Add($this.CopyField("firstname", "_text_"))
        $CustomerManagedSchema.Fields.Add($this.CopyField("lastname", "_text_"))

        $this.Collections["9.2"].Add($CustomerManagedSchema)
    }

    hidden [void] CreateOrderManagedSchema()
    {
        $OrderManagedSchema = [CollectionSchema]::new()
        $OrderManagedSchema.Name = "_orders_scope"
        $OrderManagedSchema.Parent = "(//field[@name='_text_'])"
        $OrderManagedSchema.UniqueKey = "entityid"

        $OrderManagedSchema.Fields.Add($this.Field("entityuniqueid", "string", $true, $true, $true))
        $OrderManagedSchema.Fields.Add($this.Field("entityid", "string", $true, $true, $true))
        $OrderManagedSchema.Fields.Add($this.Field("entityversion", "pint", $true, $true, $false))

        $OrderManagedSchema.Fields.Add($this.Field("email", "string", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("customerid", "string", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("orderconfirmationid", "string", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("status", "string", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("orderplaceddate", "pdate", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("datecreated", "pdate", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("dateupdated", "pdate", $true, $true, $false))
        $OrderManagedSchema.Fields.Add($this.Field("artifactstoreid", "string", $true, $true, $false))

        $OrderManagedSchema.Fields.Add($this.CopyField("email", "_text_"))
        $OrderManagedSchema.Fields.Add($this.CopyField("orderconfirmationid", "_text_"))
        $OrderManagedSchema.Fields.Add($this.CopyField("status", "_text_"))

        $this.Collections["9.2"].Add($OrderManagedSchema)
    }

    hidden [SchemaField] Field([string] $Name, [string] $Type, [bool] $Indexed, [bool] $Stored, [bool] $Required)
    {
        $Field = [SchemaField]::new()
        $Field.Element = "field"
        $Field.Identifier = "name"
        $Field.IdentifierValue = $Name
        $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "name"; Value = $Name; }))
        $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "type"; Value = $Type; }))

        if ($Indexed)
        {
            $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "indexed"; Value = "true"; }))
        }

        if ($Stored)
        {
            $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "stored"; Value = "true"; }))
        }

        if ($Required)
        {
            $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "required"; Value = "true"; }))
        }

        return $Field
    }

    hidden [SchemaField] CopyField([string] $Source, [string] $Dest)
    {
        $Field = [SchemaField]::new()

        $Field.Element = "copyField"
        $Field.Identifier = "source"
        $Field.IdentifierValue = $Source
        $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "source"; Value = $Source; }))
        $Field.Attributes.Add((New-Object SchemaFieldAttribute -Property @{ Name = "dest"; Value = $Dest; }))

        return $Field
    }
}

class ConfigSchema
{
    [string] $Name
    [System.Collections.Generic.List[[ConfigField]]] $Fields = [System.Collections.Generic.List[ConfigField]]::new()
}

class ConfigField
{
    [string] $XPath
    [string] $Attribute
    [string] $Value
}

class CollectionSchema
{
    [string] $Name
    [string] $Parent
    [string] $UniqueKey
    [System.Collections.Generic.List[[SchemaField]]] $Fields = [System.Collections.Generic.List[[SchemaField]]]::new()
}

class SchemaField
{
    [string] $Element
    [string] $Identifier
    [string] $IdentifierValue
    [System.Collections.Generic.List[SchemaFieldAttribute]] $Attributes = [System.Collections.Generic.List[SchemaFieldAttribute]]::new()
}

class SchemaFieldAttribute
{
    [string] $Name
    [string] $Value
}

class Sitecore
{
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $SitecoreSolrVersionMap = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $SitecoreSolrIndexMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $XconnectSolrIndexMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $CommerceSolrIndexMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $SxaSolrIndexMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.Generic.Dictionary[[string],[string]]]]] $IndexAliasMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.Generic.Dictionary[[string],[string]]]]]::new()

    hidden [SolrConfig] $SolrConfig = [SolrConfig]::new()
    hidden [ManagedSchema] $ManagedSchema = [ManagedSchema]::new()

    Sitecore()
    {
        $this.PopulateSitecoreSolrVersionMap()
        $this.PopulateSitecoreSolrIndexMap()
        $this.PopulateXconnectSolrIndexMap()
        $this.PopulateCommerceSolrIndexMap()
        $this.PopulateSxaSolrIndexMap()
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

    hidden [void] PopulateCommerceSolrIndexMap()
    {
        $this.CommerceSolrIndexMap.Add("9.2", @("_catalog_items_scope","_customers_scope","_orders_scope"))
    }
    
    hidden [void] PopulateSxaSolrIndexMap()
    {
        $this.SxaSolrIndexMap.Add("9.2", @("_sxa_master_index", "_sxa_web_index"))
    }

    hidden [void] PopulateIndexAliasMap()
    {
        $this.IndexAliasMap.Add("9.2", [System.Collections.Generic.Dictionary[[string],[string]]]::new())
        $this.IndexAliasMap["9.2"].Add("_xdb", "xdb")
        $this.IndexAliasMap["9.2"].Add("_xdb_rebuild", "xdb_rebuild")
        $this.IndexAliasMap["9.2"].Add("_catalog_items_scope", "CatalogItemsScope")
        $this.IndexAliasMap["9.2"].Add("_customers_scope", "CustomersScope")
        $this.IndexAliasMap["9.2"].Add("_orders_scope", "OrdersScope")
    }

    hidden [ConfigSchema] GetSolrConfigPatchMap([string] $SitecoreVersion, [string] $CollectionName)
    {
        return ($this.SolrConfig.Configs[$SitecoreVersion] | Where-Object { $CollectionName -match $_.Name } | Select-Object -First 1)
    }

    hidden [CollectionSchema] GetManagedSchemaPatchMap([string] $SitecoreVersion, [string] $CollectionName)
    {
        return ($this.ManagedSchema.Collections[$SitecoreVersion] | Where-Object { $CollectionName -match $_.Name } | Select-Object -First 1)
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

    [System.Collections.ArrayList] GetCommerceSolrIndexArray([string] $SitecoreVersion)
    {
        return $this.CommerceSolrIndexMap[$SitecoreVersion]
    }

    [System.Collections.ArrayList] GetSxaSolrIndexArray([string] $SitecoreVersion)
    {
        return $this.SxaSolrIndexMap[$SitecoreVersion]
    }

    [System.Collections.Generic.Dictionary[[string],[string]]] GetIndexAliases([string] $SitecoreVersion)
    {
        return $this.IndexAliasMap[$SitecoreVersion]
    }

    [void] PatchSitecoreIndexSolrConfig([string] $SitecoreVersion, [SolrCollection] $Collection)
    {
        $CollectionFolderPath = $Collection.GetConfigSetPath()
        $ConfigSchema = $this.GetSolrConfigPatchMap($SitecoreVersion, $Collection.GetName())

        $XmlFilePath = (Get-ChildItem -Path $CollectionFolderPath -Filter "solrconfig.xml" | Select-Object -ExpandProperty FullName)

        Write-Host "Patching solrconfig.xml for $($CollectionFolderPath) ... " -NoNewline

        if ($null -ne $ConfigSchema)
        {
            switch ($SitecoreVersion)
            {
                "9.2" {

                    foreach ($Field in $ConfigSchema.Fields)
                    {
                        [XmlUtil]::SetXmlAttributeValue($XmlFilePath, $Field.XPath, $Field.Attribute, $Field.Value)
                    }
                }
            }
        }

        Write-Host "Done"
    }

    [void] PatchSitecoreIndexManagedSchema([string] $SitecoreVersion, [SolrCollection] $Collection)
    {
        $CollectionFolderPath = $Collection.GetConfigSetPath()
        $CollectionSchema = $this.GetManagedSchemaPatchMap($SitecoreVersion, $Collection.GetName())

        $XmlFilePath = (Get-ChildItem -Path $CollectionFolderPath -Filter "managed-schema" | Select-Object -ExpandProperty FullName)

        Write-Host "Patching managed-schema for $($CollectionFolderPath) ... " -NoNewline

        if ($null -ne $CollectionSchema)
        {
            switch ($SitecoreVersion)
            {
                "9.2" {

                    [XmlUtil]::SetXmlElementValue($XmlFilePath, "//uniqueKey", $CollectionSchema.UniqueKey)

                    $Parent = $CollectionSchema.Parent

                    foreach ($Field in $CollectionSchema.Fields)
                    {
                        [XmlUtil]::NewXmlElementAndAttributeAfter($XmlFilePath, $Parent, $Field.Element, $Field.Identifier, $Field.IdentifierValue)

                        foreach ($Attribute in $Field.Attributes)
                        {
                            [XmlUtil]::SetXmlAttributeValue($XmlFilePath, "(//$($Field.Element)[@$($Field.Identifier)='$($Field.IdentifierValue)'])[1]", $Attribute.Name, $Attribute.Value)
                        }

                        $Parent = "(//$($Field.Element)[@$($Field.Identifier)='$($Field.IdentifierValue)'])"
                    }

                }
            }
        }

        Write-Host "Done"
    }

    [void] PatchCommerceIndexManagedSchema([string] $SitecoreVersion, [SolrCollection] $Collection)
    {
        $CollectionFolderPath = $Collection.GetConfigSetPath()
        $CollectionSchema = $this.GetManagedSchemaPatchMap($SitecoreVersion, $Collection.GetName())

        $XmlFilePath = (Get-ChildItem -Path $CollectionFolderPath -Filter "managed-schema" | Select-Object -ExpandProperty FullName)

        Write-Host "Patching managed-schema for $($CollectionFolderPath) ... " -NoNewline

        if ($null -ne $CollectionSchema)
        {
            switch ($SitecoreVersion)
            {
                "9.2" {

                    [XmlUtil]::SetXmlElementValue($XmlFilePath, "//uniqueKey", $CollectionSchema.UniqueKey)

                    $Parent = $CollectionSchema.Parent

                    foreach ($Field in $CollectionSchema.Fields)
                    {
                        [XmlUtil]::NewXmlElementAndAttributeAfter($XmlFilePath, $Parent, $Field.Element, $Field.Identifier, $Field.IdentifierValue)

                        foreach ($Attribute in $Field.Attributes)
                        {
                            [XmlUtil]::SetXmlAttributeValue($XmlFilePath, "(//$($Field.Element)[@$($Field.Identifier)='$($Field.IdentifierValue)'])[1]", $Attribute.Name, $Attribute.Value)
                        }

                        $Parent = "(//$($Field.Element)[@$($Field.Identifier)='$($Field.IdentifierValue)'])"
                    }

                    [XmlUtil]::DeleteXmlElementValue($XmlFilePath, "(//field[@name='id'])")

                }
            }
        }

        Write-Host "Done"

    }
}

class Solr
{
    hidden [string] $SolrVersion
    hidden [string] $SolrArchiveUrl
    hidden [string] $SolrArchiveFormat = "solr-{0}.zip"

    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $SolrVersionMap = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $SolrChecksumMap = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $SolrBaseConfigMap = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]] $SolrConfigSetMap = [System.Collections.Generic.Dictionary[[string],[System.Collections.ArrayList]]]::new()

    Solr()
    {
        $this.SetSolrVersionMap()
        $this.SetSolrChecksumMap()
        $this.SetSolrBaseConfigMap()
        $this.SetSolrConfigSetMap()
    }

    hidden [void] SetSolrVersionMap()
    {
        $this.SolrVersionMap.Add("9.2", "7.5.0")
    }

    hidden [void] SetSolrChecksumMap()
    {
        $this.SolrChecksumMap.Add("9.2", "085EB16912DD91B40DFFEC363554CB434DB6AFF928761A9C1B852A56172C0C9A1026A875A10C3D1C8DC6D992E29BC2B273E83EB07876E544542AB44CE91407F1")
    }

    hidden [void] SetSolrBaseConfigMap()
    {
        $this.SolrBaseConfigMap.Add("9.2", "_default")
    }

    hidden [void] SetSolrConfigSetMap()
    {
        $this.SolrConfigSetMap.Add("9.2", @("server","solr","configsets"))
    }

    [string] GetSolrVersion([string] $SitecoreVersion)
    {
        return $this.SolrVersionMap[$SitecoreVersion]
    }

    [string] GetSolrChecksum([string] $SitecoreVersion)
    {
        return $this.SolrChecksumMap[$SitecoreVersion]
    }

    [string] GetSolrBaseConfig([string] $SitecoreVersion)
    {
        return $this.SolrBaseConfigMap[$SitecoreVersion]
    }

    [System.Collections.ArrayList] GetSolrConfigSet([string] $SitecoreVersion)
    {
        return $this.SolrConfigSetMap[$SitecoreVersion]
    }

    [string] GetSolrArchiveName([string] $SitecoreVersion)
    {
        return [string]::Format($this.SolrArchiveFormat, $this.GetSolrVersion($SitecoreVersion))
    }

    [string] GetSolrArchiveUrl([string] $SitecoreVersion)
    {
        return [string]::Format("https://archive.apache.org/dist/lucene/solr/{0}/{1}", $this.GetSolrVersion($SitecoreVersion), $this.GetSolrArchiveName($SitecoreVersion))
    }

    [string] GetSolrArchivePath([string] $SitecoreVersion)
    {
        return Join-Path -Path ([Constants]::GetInstance().WorkingDir) -ChildPath $this.GetSolrArchiveName($SitecoreVersion)
    }

    [System.Collections.ArrayList] GetExistingConfigs()
    {
        $Configs = [System.Collections.ArrayList]::new()

        if (Test-Path -Path ([Constants]::GetInstance().IndexesWorkingDir))
        {
            Get-ChildItem -Path ([Constants]::GetInstance().IndexesWorkingDir) -Directory | Select-Object -ExpandProperty Name | ForEach-Object { $Configs.Add($_) }
        }

        return $Configs
    }

    [bool] CheckIfSolrArchiveExists([string] $SitecoreVersion)
    {
        $Result = (Test-Path -Path $this.GetSolrArchivePath($SitecoreVersion))

        Write-Host ([string]::Format("Checking if {0} exists ... ", $this.GetSolrArchiveName($SitecoreVersion))) -NoNewline

        if (!$Result)
        {
            Write-Host "Not found"
        }
        else
        {
            Write-Host "Found"
        }

        return $Result
    }

    [bool] IsSolrArchiveChecksumValid([string] $SitecoreVersion)
    {
        $Result = ($this.GetSolrChecksum($SitecoreVersion) -eq (Get-FileHash -Path $this.GetSolrArchivePath($SitecoreVersion) -Algorithm SHA512).Hash)

        Write-Host ([string]::Format("Validating {0} checksum using SHA-512 hash ... ", $this.GetSolrArchiveName($SitecoreVersion))) -NoNewline

        if (!$Result)
        {
            Write-Host "Invalid"
        }
        else
        {
            Write-Host "Valid"
        }

        return $Result
    }

    [bool] CheckIfMinimalConfigSetExists()
    {
        $Result = (Test-Path -Path ([Constants]::GetInstance().ConfigSetWorkingDir))

        Write-Host "Checking if minimal config set already exists ... " -NoNewline

        if (!$Result)
        {
            Write-Host "Not found"
        }
        else
        {
            Write-Host "Found"
        }

        return $Result
    }

    [bool] CheckIfExistingConfigSetsExist()
    {
        $Result = ($this.GetExistingConfigs().Count -gt 0)

        Write-Host "Check if there are existing local config sets ... " -NoNewline

        if (!$Result)
        {
            Write-Host "Not found"
        }
        else
        {
            Write-Host "Found"
        }

        return $Result
    }

    [void] DownloadSolrArchive([string] $SitecoreVersion)
    {
        if (!$this.CheckIfSolrArchiveExists($SitecoreVersion))
        {
            Write-Host ([string]::Format("Downloading {0} ... ", $this.GetSolrArchiveName($SitecoreVersion))) -NoNewline

            ([System.Net.WebClient]::new()).DownloadFile($this.GetSolrArchiveUrl($SitecoreVersion), $this.GetSolrArchivePath($SitecoreVersion))

            Write-Host "Done"
        }
    }

    [void] ExtractSolrArchive([string] $SitecoreVersion)
    {
        if (Test-Path -Path ([Constants]::GetInstance().SolrWorkingDir))
        {
            Remove-Item -Path ([Constants]::GetInstance().SolrWorkingDir) -Recurse -Force
        }

        Write-Host ([string]::Format("Extracting contents of {0} to {1} ... ", $this.GetSolrArchiveName($SitecoreVersion), ([Constants]::GetInstance().SolrWorkingDir))) -NoNewline

        Expand-Archive -Path $this.GetSolrArchivePath($SitecoreVersion) -DestinationPath ([Constants]::GetInstance().SolrWorkingDir)

        Write-Host "Done"
    }

    [string] FindMinimalSolrConfig([string] $SitecoreVersion)
    {
        return (Get-ChildItem -Path ([Constants]::GetInstance().SolrWorkingDir) -Recurse | Where-Object { $_.Name -eq $this.GetSolrBaseConfig($SitecoreVersion) } | Select-Object -ExpandProperty FullName)
    }

    [void] CopyMinimalSolrConfigToConfigSetWorkingDir([string] $SitecoreVersion)
    {
        if (Test-Path -Path ([Constants]::GetInstance().ConfigSetWorkingDir))
        {
            Remove-Item -Path ([Constants]::GetInstance().ConfigSetWorkingDir) -Recurse -Force
        }

        Write-Host ([string]::Format("Copying minimal config to {0} ... ", ([Constants]::GetInstance().ConfigSetWorkingDir))) -NoNewline

        Copy-Item -Path (Join-Path -Path $this.FindMinimalSolrConfig($SitecoreVersion) -ChildPath "conf") -Destination ([Constants]::GetInstance().ConfigSetWorkingDir) -Recurse

        Write-Host "Done"
    }
}

class SolrCollection
{
    hidden [string] $Name

    hidden [string] $ArchivePath

    [CollectionStatus] $Status

    SolrCollection()
    {
    }

    SolrCollection([string]$Name)
    {
        $this.Name = $Name
    }

    [string] GetName()
    {
        return $this.Name
    }

    [string] GetConfigSetPath()
    {
        return [string]::Format("{0}{1}{2}", [Constants]::GetInstance().IndexesWorkingDir, [System.IO.Path]::DirectorySeparatorChar, $this.GetName())
    }

    [void] CreateConfigSetFromMinimalSolrConfig()
    {
        Write-Host ([string]::Format("Cloning minimal config set for {0} ... ", $this.GetName())) -NoNewLine

        Copy-Item -Path ([Constants]::GetInstance().ConfigSetWorkingDir) -Destination $this.GetConfigSetPath() -Recurse -Force

        Write-Host "Done"
    }

    [System.Collections.ArrayList] GetConfigSetFiles()
    {
        $Files = [System.Collections.ArrayList]::new()

        if (Test-Path -Path $this.GetConfigSetPath())
        {
            Get-ChildItem -Path $this.GetConfigSetPath() -File -Recurse | Select-Object -ExpandProperty FullName | ForEach-Object { $Files.Add($_) }
        }

        return $Files
    }

    [string] GetArchiveName()
    {
        return ([System.IO.Path]::GetFileName($this.ArchivePath))
    }

    [string] GetArchivePath()
    {
        return $this.ArchivePath
    }

    [void] RemoveArchive()
    {
        if ($null -eq $this.ArchivePath)
        {
            return
        }

        if (Test-Path -Path $this.ArchivePath)
        {
            Write-Host ([string]::Format("Removing archive {0} for config set {1} ... ", $this.GetArchiveName(), $this.GetName())) -NoNewline

            Remove-Item -Path $this.ArchivePath -Force

            Write-Host "Done"
        }
    }

    [void] CreateArchive()
    {
        if (!(Test-Path -Path ([Constants]::GetInstance().ConfigSetUploadDir)))
        {
            New-Item -Path ([Constants]::GetInstance().ConfigSetUploadDir) -ItemType "Directory" | Out-Null
        }

        $this.ArchivePath = Join-Path -Path ([Constants]::GetInstance().ConfigSetUploadDir) -ChildPath ([string]::Format("{0}.zip", [Guid]::NewGuid().ToString("D")))

        Write-Host ([string]::Format("Creating new archive {0} for config set {1} ... ", $this.GetArchiveName(), $this.GetName())) -NoNewline

		Get-ChildItem -Path $this.GetConfigSetPath() | Compress-Archive -DestinationPath $this.ArchivePath -CompressionLevel "Fastest"

        Write-Host "Done"
    }
}

class SearchStaxProvider
{
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $AuthTokenHeaders = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $AuthBasicHeaders = [System.Collections.Generic.Dictionary[[string],[string]]]::new()

    hidden [string] $AccountName
    hidden [string] $DeploymentUid
    hidden [string] $Username
    hidden [string] $Password
    hidden [string] $SitecoreVersion
    hidden [string] $SolrUsername
    hidden [string] $SolrPassword

    hidden [string] $BaseUrl = "https://app.searchstax.com"
    hidden [string] $AuthUrl = [string]::Format("{0}/api/rest/v2/obtain-auth-token/", $this.BaseUrl)
    hidden [string] $DeploymentUrl
    hidden [string] $ConfigListUrl
    hidden [string] $ConfigDeleteUrl
    hidden [string] $ConfigUploadUrl
    hidden [System.Collections.ArrayList] $ExistingCollections = [System.Collections.ArrayList]::new()

    hidden [string] $ListCollectionsUrl = "{0}admin/collections?action=LIST"
    hidden [string] $CreateCollectionUrl = "{0}admin/collections?action=CREATE&name={1}&numShards=1&replicationFactor={2}&collection.configName={3}"
    hidden [string] $CreateCollectionAliasUrl = "{0}admin/collections?action=CREATEALIAS&name={1}&collections={2}"
    hidden [string] $DeleteCollectionAliasUrl = "{0}admin/collections?action=DELETEALIAS&name={1}"

    SearchStaxProvider([string] $AccountName, [string] $DeploymentUid, [string] $Username, [string] $Password, [string] $SolrUsername, [string] $SolrPassword)
    {
        $this.AccountName = $AccountName
        $this.DeploymentUid = $DeploymentUid
        $this.Username = $Username
        $this.Password = $Password
        $this.SolrUsername = $SolrUsername
        $this.SolrPassword = $SolrPassword

        $this.SetDeploymentUrl($AccountName, $DeploymentUid)
        $this.SetConfigListUrl($AccountName, $DeploymentUid)
        $this.SetConfigDeleteUrl($AccountName, $DeploymentUid)
        $this.SetConfigUploadUrl($AccountName, $DeploymentUid)

        $this.SetAuthBasicHeaders()
        $this.SetAuthTokenHeaders()

        $this.SetExistingCollections()
    }

    hidden [void] SetDeploymentUrl([string] $AccountName, [string] $DeploymentUid)
    {
        $this.DeploymentUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void] SetConfigListUrl([string] $AccountName, [string] $DeploymentUid)
    {
        $this.ConfigListUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/zookeeper-config/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void] SetConfigDeleteUrl([string] $AccountName, [string] $DeploymentUid)
    {
        $this.ConfigDeleteUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/zookeeper-config/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void] SetConfigUploadUrl([string] $AccountName, [string] $DeploymentUid)
    {
        $this.ConfigUploadUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/zookeeper-config/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void] SetAuthBasicHeaders()
    {
        if ($this.AuthBasicHeaders.ContainsKey("Authorization"))
        {
            $this.AuthBasicHeaders.Remove("Authorization")
        }

        if (!([string]::IsNullOrEmpty($this.SolrUsername)) -and !([string]::IsNullOrEmpty($this.SolrPassword)))
        {
            $this.AuthBasicHeaders.Add("Authorization", [string]::Format("Basic {0}", [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes([string]::Format("{0}:{1}", $this.SolrUsername, $this.SolrPassword)))))
        }
    }

    hidden [void] SetAuthTokenHeaders()
    {
        $requestBody = @{
            username=$this.Username
            password=$this.Password
        }

        $requestBody = $requestBody | ConvertTo-Json

        Write-Host "Contacting SearchStax to retrieve authorization token ... " -NoNewline

        try
        {
            if ($this.AuthTokenHeaders.ContainsKey("Authorization"))
            {
                $this.AuthTokenHeaders.Remove("Authorization")
            }

            $this.AuthTokenHeaders.Add("Authorization", [string]::Format("Token {0}", (Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri $this.AuthUrl -Body $requestBody).token))

            Write-Host "Success"
        }
        catch
        {
            Write-Host "Failed"

            Write-Error -Message "Unable to get authentication token. Error was: $_" -ErrorAction Stop
        }
    }

    [bool] CheckIfDeploymentExists()
    {
        $Result = $false

        try
        {

            $Response = Invoke-WebRequest -Method Get -Headers $this.AuthTokenHeaders -Uri $this.DeploymentUrl

            if ($Response.StatusCode -eq 200)
            {
                $Result = $true
            }
            else
            {
                Write-Error -Message "Could not find deployment. Exiting" -ErrorAction Stop
            }

        }
        catch
        {
            Write-Error -Message "Unable to verify if the deployment exists. Error was: $_" -ErrorAction Stop
        }

        return $Result
    }

    hidden [object] GetDeploymentInfo()
    {
        $Result = $null

        try
        {
            $Result = (Invoke-RestMethod -Method Get -ContentType 'application/json' -Headers $this.AuthTokenHeaders -Uri $this.DeploymentUrl)
        }
        catch
        {
            Write-Error -Message "Unable to retrieve deployment information. Error was: $_" -ErrorAction Stop
        }

        return $Result
    }

    [string] GetDeploymentSolrUrl()
    {
        $Info = $this.GetDeploymentInfo()

        if ($null -ne $Info)
        {
            return $Info.http_endpoint
        }

        return [string]::Empty
    }

    [int] GetDeploymentNodeCount()
    {
        $deploymentInfo = $this.GetDeploymentInfo()

        if ($null -eq $deploymentInfo)
        {
            return -1
        }

        return (([int]$deploymentInfo.num_nodes_default) + ([int]$deploymentInfo.num_additional_app_nodes))
    }

    [int] GetRemoteConfigSetFileCount([SolrCollection] $Collection, [int] $Retry, [int] $RetryMax)
    {
        $Result = 0

        try
        {
            Write-Host ([string]::Format("({0}/{1}) Retrieving file count for remote config {2} ... ", $Retry, $RetryMax, $Collection.GetName())) -NoNewline

            $Result = (Invoke-RestMethod -Method Get -Headers $this.AuthTokenHeaders -Uri ([string]::Format("{0}{1}/", $this.ConfigListUrl, $Collection.GetName()))).configs.Count

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }

        return $Result
    }

    [void] RemoveRemoteConfigSet([SolrCollection] $Collection, [string] $Message)
    {
        $Result = $false

        Write-Host $Message -NoNewline

        try
        {
            $Response = Invoke-RestMethod -Method Delete -Headers $this.AuthTokenHeaders -Uri ([string]::Format("{0}{1}/", $this.ConfigDeleteUrl, $Collection.GetName()))
            
            $Result = ($Response.success -eq "true")
        }
        catch
        {

        }

        if (!$Result)
        {
            Write-Host "Failed"
        }
        else
        {
            Write-Host "Done"
        }

        Write-Host ([string]::Format("Sleeping for {0} seconds ... ", ([Constants]::GetInstance().SleepSeconds))) -NoNewline

        Start-Sleep -Seconds ([Constants]::GetInstance().SleepSeconds)

        Write-Host "Done"
    }

    [void] UploadConfigSet([SolrCollection] $Collection)
    {
        $RetryCount = 1
        $RetryMaxCount = [Constants]::GetInstance().RetryMaxCount

        while (!($RetryCount -gt $RetryMaxCount))
        {
            $Collection.RemoveArchive()
            $Collection.CreateArchive()

            $Form = @{
                name = $Collection.GetName()
                files = Get-Item -Path $Collection.GetArchivePath()
            }

            Write-Host ([string]::Format("({0}/{1}) Uploading config set archive for {2} to SearchStax ... ", $RetryCount, $RetryMaxCount, $Collection.GetName())) -NoNewline

            try
            {
                Invoke-RestMethod -Method Post -Form $Form -Headers $this.AuthTokenHeaders -Uri $this.ConfigUploadUrl | Out-Null

                Write-Host "Done"
            }
            catch
            {
                Write-Host "Failed"

                Write-Verbose -Message ([string]::Format("({0}/{1}) Unable to upload config set {2}. Error was: {3}", $RetryCount, $RetryMaxCount, $Collection.GetName(), $_.Exception.Message)) -ErrorAction SilentlyContinue
            }

            $LocalFileCount = $Collection.GetConfigSetFiles().Count
            $RemoteFileCount = $this.GetRemoteConfigSetFileCount($Collection, $RetryCount, $RetryMaxCount)

            if ($RemoteFileCount -eq $LocalFileCount)
            {
                break
            }

            $this.RemoveRemoteConfigSet($Collection, [string]::Format("({0}/{1}) Remote config set {2} is being removed as it has an incorrect file count ({3} != {4}) ... ", $RetryCount, $RetryMaxCount, $Collection.GetName(), $RemoteFileCount, $LocalFileCount))

            $RetryCount = $RetryCount + 1
        }

        if ($RetryCount -ge $RetryMaxCount)
        {
            Write-Host ([string]::Format("Skipping upload of config set {0}", $Collection.GetName()))

            $Collection.Status = [CollectionStatus]::UploadFailed
        }
        else
        {
            Write-Host ([string]::Format("Config set {0} uploaded successfully", $Collection.GetName()))

            $Collection.Status = [CollectionStatus]::UploadSuccess
        }
    }

    [void] SetExistingCollections()
    {
        Write-Host "Retrieving list of existing Solr collections ... " -NoNewline

        try
        {
            $Result = Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.ListCollectionsUrl, $this.GetDeploymentSolrUrl()))

            if ([bool]$Result.PSObject.Properties.name -contains "collections")
            {
                foreach ($Collection in $Result.Collections)
                {
                    $this.ExistingCollections.Add($Collection)
                }
            }

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }
    }

    [bool] SkipCollection([SolrCollection] $Collection)
    {
        return ($this.ExistingCollections -contains $Collection.GetName())
    }

    [void] CreateCollection([SolrCollection] $Collection)
    {
        Write-Host ([string]::Format("Creating Solr collection {0} ... ", $Collection.GetName())) -NoNewline

        try
        {
            Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.CreateCollectionUrl, $this.GetDeploymentSolrUrl(), $Collection.GetName(), $this.GetDeploymentNodeCount(), $Collection.GetName()))

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }
    }

    [void] RemoveCollectionAlias([SolrCollection] $Collection, [System.Collections.Generic.Dictionary[[string],[string]]] $IndexAliases)
    {
        foreach ($IndexSuffix in $IndexAliases.Keys)
        {
            if ($Collection.GetName() -like ([string]::Format("*{0}", $IndexSuffix)))
            {
                Write-Host ([string]::Format("Removing Solr alias {0} if it exists ... ", $IndexAliases[$IndexSuffix])) -NoNewline

                try
                {
                    Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.DeleteCollectionAliasUrl, $this.GetDeploymentSolrUrl(), $IndexAliases[$IndexSuffix]))

                    Write-Host "Done"
                }
                catch
                {
                    Write-Host "Failed"
                }
            }
        }
    }

    [void] CreateCollectionAlias([SolrCollection] $Collection, [System.Collections.Generic.Dictionary[[string],[string]]] $IndexAliases)
    {
        foreach ($IndexSuffix in $IndexAliases.Keys)
        {
            if ($Collection.GetName() -like ([string]::Format("*{0}", $IndexSuffix)))
            {
                Write-Host ([string]::Format("Creating Solr alias {0} for collection {1} ... ", $IndexAliases[$IndexSuffix], $Collection.GetName())) -NoNewline

                try
                {
                    Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.CreateCollectionAliasUrl, $this.GetDeploymentSolrUrl(), $IndexAliases[$IndexSuffix], $Collection.GetName()))

                    Write-Host "Done"
                }
                catch
                {
                    Write-Host "Failed"
                }
            }
        }
    }
}

class SearchStaxCollectionManager
{
    hidden [Solr] $Solr
    hidden [Sitecore] $Sitecore
    hidden [SearchStaxProvider] $SearchStaxProvider
    hidden [System.Collections.Generic.List[SolrCollection]] $SolrCollections

    hidden [string] $SitecoreVersion
    hidden [string] $IndexPrefix
    hidden [string] $InstallMode
    hidden [bool] $DryRun

    SearchStaxCollectionManager()
    {
    }

    SearchStaxCollectionManager([string] $AccountName, [string] $DeploymentUid, [string] $IndexPrefix, [string] $Username, [string] $Password, [string] $SitecoreVersion, [string] $InstallMode, [string] $SolrUsername, [string] $SolrPassword, [bool] $DryRun)
    {
        $this.Solr = [Solr]::new()
        $this.Sitecore = [Sitecore]::new()
        $this.SearchStaxProvider = [SearchStaxProvider]::new($AccountName.Trim(), $DeploymentUid.Trim(), $Username.Trim(), $Password.Trim(), $SolrUsername.Trim(), $SolrPassword.Trim())
        $this.SolrCollections = [System.Collections.Generic.List[SolrCollection]]::new()

        $this.SitecoreVersion = $SitecoreVersion.Trim()
        $this.IndexPrefix = $IndexPrefix.Trim()
        $this.InstallMode = $InstallMode.Trim()
        $this.DryRun = $DryRun
    }

    [void] Clean()
    {
        $Constants = ([Constants]::GetInstance())
        
		if (Test-Path $Constants.SolrWorkingDir)
		{
			Remove-Item -Path $Constants.SolrWorkingDir -Recurse -Force
		}
		
		if (Test-Path $Constants.IndexesWorkingDir)
		{
			Remove-Item -Path $Constants.IndexesWorkingDir -Recurse -Force
		}
		
		if (Test-Path $Constants.ConfigSetUploadDir)
		{
			Remove-Item -Path $Constants.ConfigSetUploadDir -Recurse -Force
		}
		
		if (Test-Path $Constants.ConfigSetUploadDir)
		{
			Remove-Item -Path $Constants.ConfigSetWorkingDir -Recurse -Force
		}
    }

    [void] Execute()
    {
        if (!$this.SearchStaxProvider.CheckIfDeploymentExists())
        {
            Write-Error -Message "Cannot find a deployment with the provided UID" -ErrorAction Stop
        }

        if (!$this.Solr.CheckIfSolrArchiveExists($this.SitecoreVersion))
        {
            $this.Solr.DownloadSolrArchive($this.SitecoreVersion)
        }

        if ($this.Solr.IsSolrArchiveChecksumValid($this.SitecoreVersion))
        {
            $this.Solr.ExtractSolrArchive($this.SitecoreVersion)
            $this.Solr.CopyMinimalSolrConfigToConfigSetWorkingDir($this.SitecoreVersion)
        }

        $CollectionSource = switch ($this.InstallMode)
        {
            'SXA' {
                $this.Sitecore.GetSxaSolrIndexArray($this.SitecoreVersion)
            }
            'XConnect' {
                $this.Sitecore.GetXconnectSolrIndexArray($this.SitecoreVersion)
                break
            }
            'Commerce' {
                $this.Sitecore.GetCommerceSolrIndexArray($this.SitecoreVersion)
                break
            }
            default {
                $this.Sitecore.GetSitecoreSolrIndexArray($this.SitecoreVersion)
                break
            }
        }

        $this.Solr.GetExistingConfigs() + ($CollectionSource | ForEach-Object { [string]::Format("{0}{1}", $this.IndexPrefix, $_) }) | Select-Object -Unique | ForEach-Object {
            
            Write-Host ([string]::Format("Creating new collection {0}", $_))
            
            $this.SolrCollections.Add([SolrCollection]::new($_))

        }

        foreach ($SolrCollection in $this.SolrCollections)
        {
            if ($this.SearchStaxProvider.SkipCollection($SolrCollection))
            {
                Write-Host ([string]::Format("Collection {0} already exists. Skipping", $SolrCollection.GetName()))

                Continue
            }

            if ($SolrCollection.GetConfigSetFiles().Count -le 0)
            {
                $SolrCollection.CreateConfigSetFromMinimalSolrConfig()

                switch ($this.InstallMode)
                {
                    'SXA' {
                        $this.Sitecore.PatchSitecoreIndexSolrConfig($this.SitecoreVersion, $SolrCollection)
                        $this.Sitecore.PatchSitecoreIndexManagedSchema($this.SitecoreVersion, $SolrCollection)
                        break
                    }
                    'XConnect' {
                        $this.Sitecore.PatchSitecoreIndexSolrConfig($this.SitecoreVersion, $SolrCollection)
                        $this.Sitecore.PatchSitecoreIndexManagedSchema($this.SitecoreVersion, $SolrCollection)
                        break
                    }
                    'Commerce' {
                        $this.Sitecore.PatchSitecoreIndexSolrConfig($this.SitecoreVersion, $SolrCollection)
                        $this.Sitecore.PatchCommerceIndexManagedSchema($this.SitecoreVersion, $SolrCollection)
                        break
                    }
                    default {
                        $this.Sitecore.PatchSitecoreIndexSolrConfig($this.SitecoreVersion, $SolrCollection)
                        $this.Sitecore.PatchSitecoreIndexManagedSchema($this.SitecoreVersion, $SolrCollection)
                        break
                    }
                }

            }

            if (!$this.DryRun)
            {
                $this.SearchStaxProvider.UploadConfigSet($SolrCollection)

                if ($SolrCollection.Status -eq [CollectionStatus]::UploadSuccess)
                {
                    $this.SearchStaxProvider.CreateCollection($SolrCollection)
                    $this.SearchStaxProvider.RemoveCollectionAlias($SolrCollection, $this.Sitecore.GetIndexAliases($this.SitecoreVersion))
                    $this.SearchStaxProvider.CreateCollectionAlias($SolrCollection, $this.Sitecore.GetIndexAliases($this.SitecoreVersion))
                }
            }
        }
    }
}

$SearchStaxCollectionManager = [SearchStaxCollectionManager]::new($AccountName, $DeploymentUid, $IndexPrefix, $Username, $Password, $SitecoreVersion, $InstallMode, $SolrUsername, $SolrPassword, $DryRun)

if ($Clean -eq $true)
{
    $SearchStaxCollectionManager.Clean()
}

$SearchStaxCollectionManager.Execute()