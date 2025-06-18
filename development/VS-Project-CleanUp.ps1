$path = "P:\Projects\switch-recursion\"

$redundantBuildConfigs = @(
    "'`$(Configuration)' == 'Dev'",
    "'`$(Configuration)' == 'CI'",
    "'`$(Configuration)' == 'QA'",
    "'`$(Configuration)' == 'UAT'",
    "'`$(Configuration)' == 'Build'",
    "'`$(Configuration)' == 'Debug'",
    "'`$(Configuration)' == 'Release'",
    "'`$(Configuration)' == 'Production'",
    "'`$(Configuration)|`$(Platform)' == 'UAT|AnyCPU'",
    "'`$(Configuration)|`$(Platform)' == 'Dev|AnyCPU'",
    "'`$(Configuration)|`$(Platform)' == 'Debug|AnyCPU'",
    "'`$(Configuration)|`$(Platform)' == 'Release|AnyCPU'"
)

$defaultBuildConfigs = @(
    "'`$(Configuration)' == 'Debug'",
    "'`$(Configuration)' == 'Release'"
)

Get-ChildItem -Path $path -Recurse -Filter "*.csproj.user" | Remove-Item

Get-ChildItem -Path $path -Recurse -Filter "*.csproj" | %{

    $isDirty = $false
    $doc = [System.Xml.XmlDocument]::new()
    $doc.Load($_.FullName)

    $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace("ns", $doc.Project.NamespaceURI)

    $propertyGroups = $doc.SelectNodes("//ns:PropertyGroup[@Condition]", $ns)
    $primaryPropertyGroup = $doc.SelectSingleNode("//ns:PropertyGroup", $ns)

    for ($i = 0; $i -lt $propertyGroups.Count; $i++) {

        $propertyGroup = $propertyGroups[$i]

        if ($redundantBuildConfigs.Contains($propertyGroup.Condition.Trim())) {

            $parentNode = $propertyGroup.ParentNode;
            $parentNode.RemoveChild($propertyGroup) | Out-Null

            if (!$isDirty) {
                $isDirty = $true
            }

        }

    }

    for ($i = 0; $i -lt $defaultBuildConfigs.Count; $i++) {

        $propertyGroup = $doc.CreateElement("PropertyGroup", $doc.Project.NamespaceURI)
        $propertyGroup.SetAttribute("Condition", $defaultBuildConfigs[$i])
        $propertyGroup.RemoveAttribute("xmlns")

        $doc.Project.InsertAfter($propertyGroup, $primaryPropertyGroup) | Out-Null

        # Add debug build configuration
        if ($i -eq 0) {
            
            $debugSymbols = $doc.CreateElement("DebugSymbols", $doc.Project.NamespaceURI)
            $debugSymbols.InnerText = "true"
            $debugSymbols.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($debugSymbols) | Out-Null

            $debugType = $doc.CreateElement("DebugType", $doc.Project.NamespaceURI)
            $debugType.InnerText = "full"
            $debugType.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($debugType) | Out-Null

            $optimize = $doc.CreateElement("Optimize", $doc.Project.NamespaceURI)
            $optimize.InnerText = "false"
            $optimize.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($optimize) | Out-Null

            $outputPath = $doc.CreateElement("OutputPath", $doc.Project.NamespaceURI)
            $outputPath.InnerText = "bin\Debug\"
            $outputPath.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($outputPath) | Out-Null

            $defineConstants = $doc.CreateElement("DefineConstants", $doc.Project.NamespaceURI)
            $defineConstants.InnerText = "TRACE;DEBUG"
            $defineConstants.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($defineConstants) | Out-Null

            $errorReport = $doc.CreateElement("ErrorReport", $doc.Project.NamespaceURI)
            $errorReport.InnerText = "prompt"
            $errorReport.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($errorReport) | Out-Null

            $warningLevel = $doc.CreateElement("WarningLevel", $doc.Project.NamespaceURI)
            $warningLevel.InnerText = "4"
            $warningLevel.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($warningLevel) | Out-Null

        }
        
        # Add release build configuration
        if ($i -gt 0) {

            $debugType = $doc.CreateElement("DebugType", $doc.Project.NamespaceURI)
            $debugType.InnerText = "pdbonly"
            $debugType.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($debugType) | Out-Null

            $optimize = $doc.CreateElement("Optimize", $doc.Project.NamespaceURI)
            $optimize.InnerText = "true"
            $optimize.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($optimize) | Out-Null

            $outputPath = $doc.CreateElement("OutputPath", $doc.Project.NamespaceURI)
            $outputPath.InnerText = "bin\Release\"
            $outputPath.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($outputPath) | Out-Null

            $defineConstants = $doc.CreateElement("DefineConstants", $doc.Project.NamespaceURI)
            $defineConstants.InnerText = "TRACE"
            $defineConstants.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($defineConstants) | Out-Null

            $errorReport = $doc.CreateElement("ErrorReport", $doc.Project.NamespaceURI)
            $errorReport.InnerText = "prompt"
            $errorReport.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($errorReport) | Out-Null

            $warningLevel = $doc.CreateElement("WarningLevel", $doc.Project.NamespaceURI)
            $warningLevel.InnerText = "4"
            $warningLevel.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($warningLevel) | Out-Null

        }

        if (!$isDirty) {
            $isDirty = $true
        }

    }


    if ($isDirty) {
        $doc.Save($_.FullName)
        Write-Host "Updated $($_.FullName)"
    }

}

Get-ChildItem -Path $path -Recurse -Filter "*.scproj" | %{

    $isDirty = $false
    $doc = [System.Xml.XmlDocument]::new()
    $doc.Load($_.FullName)

    $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace("ns", $doc.Project.NamespaceURI)

    $propertyGroups = $doc.SelectNodes("//ns:PropertyGroup[@Condition]", $ns)
    $primaryPropertyGroup = $doc.SelectSingleNode("//ns:PropertyGroup", $ns)

    for ($i = 0; $i -lt $propertyGroups.Count; $i++) {

        $propertyGroup = $propertyGroups[$i]

        if ($redundantBuildConfigs.Contains($propertyGroup.Condition.Trim())) {

            $parentNode = $propertyGroup.ParentNode;
            $parentNode.RemoveChild($propertyGroup) | Out-Null

            if (!$isDirty) {
                $isDirty = $true
            }

        }

    }

    for ($i = 0; $i -lt $defaultBuildConfigs.Count; $i++) {

        $propertyGroup = $doc.CreateElement("PropertyGroup", $doc.Project.NamespaceURI)
        $propertyGroup.SetAttribute("Condition", $defaultBuildConfigs[$i])
        $propertyGroup.RemoveAttribute("xmlns")

        $doc.Project.InsertAfter($propertyGroup, $primaryPropertyGroup) | Out-Null

        # Add debug build configuration
        if ($i -eq 0) {
            
            $debugSymbols = $doc.CreateElement("DebugSymbols", $doc.Project.NamespaceURI)
            $debugSymbols.InnerText = "true"
            $debugSymbols.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($debugSymbols) | Out-Null

            $outputPath = $doc.CreateElement("OutputPath", $doc.Project.NamespaceURI)
            $outputPath.InnerText = ".\bin\Debug\"
            $outputPath.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($outputPath) | Out-Null

            $recursiveDeployAction = $doc.CreateElement("RecursiveDeployAction", $doc.Project.NamespaceURI)
            $recursiveDeployAction.InnerText = "Ignore"
            $recursiveDeployAction.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($recursiveDeployAction) | Out-Null

            $enableValidations = $doc.CreateElement("EnableValidations", $doc.Project.NamespaceURI)
            $enableValidations.InnerText = "False"
            $enableValidations.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($enableValidations) | Out-Null

        }
        
        # Add release build configuration
        if ($i -gt 0) {

            $debugSymbols = $doc.CreateElement("DebugSymbols", $doc.Project.NamespaceURI)
            $debugSymbols.InnerText = "true"
            $debugSymbols.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($debugSymbols) | Out-Null

            $outputPath = $doc.CreateElement("OutputPath", $doc.Project.NamespaceURI)
            $outputPath.InnerText = ".\bin\Release\"
            $outputPath.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($outputPath) | Out-Null

            $recursiveDeployAction = $doc.CreateElement("RecursiveDeployAction", $doc.Project.NamespaceURI)
            $recursiveDeployAction.InnerText = "Ignore"
            $recursiveDeployAction.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($recursiveDeployAction) | Out-Null

            $enableValidations = $doc.CreateElement("EnableValidations", $doc.Project.NamespaceURI)
            $enableValidations.InnerText = "False"
            $enableValidations.RemoveAttribute("xmlns")
            $propertyGroup.AppendChild($enableValidations) | Out-Null

        }

        if (!$isDirty) {
            $isDirty = $true
        }

    }


    if ($isDirty) {
        $doc.Save($_.FullName)
        Write-Host "Updated $($_.FullName)"
    }

}