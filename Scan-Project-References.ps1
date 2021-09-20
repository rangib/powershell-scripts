$path = "P:\Projects\switch-recursion\src"
$scan = "Switch.Foundation.Client.HIA"

Get-ChildItem -Path $path -Recurse -Filter "*.csproj" | %{

    $isDirty = $false

    $doc = [System.Xml.XmlDocument]::new()
    $doc.Load($_.FullName)

    $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace("ns", $doc.Project.NamespaceURI)

    $referenceNames = $doc.SelectNodes("//ns:ProjectReference/ns:Name", $ns)

    for ($i = 0; $i -lt $referenceNames.Count; $i++) {

        $referenceName = $referenceNames[$i]

        if ($referenceName.InnerText.Contains($scan)) {
            Write-Host "Found $($scan) in $($_.FullName)"
        }

    }

}