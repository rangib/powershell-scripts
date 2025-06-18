[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

Get-ChildItem -Path $Path -Recurse -Filter "license.xml" | %{

    $licenseXml = $_

    $fs = [System.IO.FileStream]::new($licenseXml.FullName, [System.IO.FileMode]::Open)
    $xr = [System.Xml.XmlTextReader]::new($fs)
    $xr.Namespaces = $false

    $doc = [System.Xml.XmlDocument]::new()
    $doc.Load($xr)

    $licensee = $doc.SelectSingleNode("//Signature/Object/license/licensee")

    Write-Host "$($licenseXml) :::: $($licensee.InnerText)"

    $fs.Close()

}