[CmdletBinding()]
param(
    [string] $Source,
    [string] $Transform
)

if (([string]::IsNullOrEmpty($Source)) -or !(Test-Path -Path $Source)) {
    throw "File not found: $($Source)"
}

if (([string]::IsNullOrEmpty($Transform)) -or !(Test-Path -Path $Transform)) {
    throw "File not found: $($Transform)"
}

$ScriptPath = (Split-Path $MyInvocation.MyCommand.Source -Parent)

Add-Type -LiteralPath "$($ScriptPath)\Microsoft.Web.XmlTransform.dll"

$XmlDoc = [Microsoft.Web.XmlTransform.XmlTransformableDocument]::new()
$XmlDoc.PreserveWhitespace = $true
$XmlDoc.Load($Source)

$XmlTransform = [Microsoft.Web.XmlTransform.XmlTransformation]::($Transform)

if ($Transform.Apply($XmlDoc) -eq $false) {
    throw "Transform failed!"
}

$XmlDoc.Save($Source)