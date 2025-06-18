using namespace System.IO
using namespace System.Xml

$path = "P:\Projects\switch-recursion\src"
$tdsGlobalPath = "P:\Projects\switch-recursion\TdsGlobal.config"
$tdsGlobalDirectory = [Path]::GetDirectoryName($tdsGlobalPath)
$projectPaths = [System.Collections.Generic.List[[string]]]::new()

$defaultNamespace = "http://schemas.microsoft.com/developer/msbuild/2003"
$defaultPublishProfileName = "Default.pubxml"

function Add-Element-To-Node {

    param(
        [XmlDocument] $XmlDocument,
        [XmlNode] $Parent,
        [string] $ElementName,
        [string] $ElementValue,
        [string] $Namespace
    )

    process
    {
        [XmlNode] $element = $XmlDocument.CreateNode("element", $ElementName, $Namespace)

        if (!([string]::IsNullOrEmpty($ElementValue))) {
            $element.InnerText = $ElementValue
        }

        $Parent.AppendChild($element) | Out-Null

        return $element
    }

}

 # Remove any existing publishing profiles
Get-ChildItem -Path $path -Recurse -Filter "*.pubxml" | Remove-Item

# Get a list of project paths
Get-ChildItem -Path $path -Recurse -Filter "*.csproj" | %{
    if (!($projectPaths.Contains($_.Directory))) {
        $projectPaths.Add($_.Directory)
    }
}

# Check if:
# - Properties folder exists (create if missing)
# - PublishProfiles folder exists (create if missing)
# Create new publish profile
$projectPaths | %{

    $propertiesPath = Join-Path -Path $_ -ChildPath "Properties"
    $publishProfilePath = Join-Path $propertiesPath -ChildPath "PublishProfiles"

    if (!(Test-Path -Path $propertiesPath)) {
        New-Item -Path $propertiesPath -ItemType Directory | Out-Null
    }

    if (!(Test-Path -Path $publishProfilePath)) {
        New-Item -Path $publishProfilePath -ItemType Directory | Out-Null
    }

    $tdsGlobalPathParts = $propertiesPath.Replace($tdsGlobalDirectory, "").Split("\")
    
    for ($i = 0; $i -lt $tdsGlobalPathParts.Count; $i++) {
        $tdsGlobalPathParts[$i] = ".."
    }

    $tdsGlobalFilePath = [string]::Join("\", $tdsGlobalPathParts)

    $xmldoc = [XmlDocument]::new()
    $xmldoc.PreserveWhitespace = $true

    $project = Add-Element-To-Node -XmlDocument $xmldoc -Parent $xmldoc -ElementName "Project" -Namespace $defaultNamespace
    $project.SetAttribute("ToolsVersion", "4.0")

    $import = Add-Element-To-Node -XmlDocument $xmldoc -Parent $project -ElementName "Import" -Namespace $defaultNamespace
    $import.SetAttribute("Project", "$($tdsGlobalFilePath)\TdsGlobal.config")

    $propertyGroup = Add-Element-To-Node -XmlDocument $xmldoc -Parent $project -ElementName "PropertyGroup" -Namespace $defaultNamespace
    
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "WebPublishMethod" -ElementValue "FileSystem" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "PublishProvider" -ElementValue "FileSystem" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "LastUsedBuildConfiguration" -ElementValue "Debug" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "LastUsedPlatform" -ElementValue "Any CPU" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "SiteUrlToLaunchAfterPublish" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "LaunchSiteAfterPublish" -ElementValue "True" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "ExcludeApp_Data" -ElementValue "False" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "publishUrl" -ElementValue "`$(SitecoreDeployFolder)" -Namespace $defaultNamespace
    Add-Element-To-Node -XmlDocument $xmldoc -Parent $propertyGroup -ElementName "DeleteExistingFiles" -ElementValue "False" -Namespace $defaultNamespace

    $publishProfileSavePath = Join-Path -Path $publishProfilePath -ChildPath $defaultPublishProfileName

    $xmlWriterSettings = [XmlWriterSettings]::new()
    $xmlWriterSettings.Indent = $true

    $xmlWriter = [XmlWriter]::Create($publishProfileSavePath, $xmlWriterSettings)

    $xmldoc.Save($xmlWriter) | Out-Null

    $xmlWriter.Dispose()

}