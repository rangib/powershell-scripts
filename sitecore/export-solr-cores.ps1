$Format = "xml"
$SolrUri = "https://localhost:8983/solr"

# Get a list of  the cores from Solr
$Cores = Invoke-RestMethod -Method Get -Uri ([string]::Format("{0}/admin/cores?action=STATUS", $SolrUri))

# Iterate over the cores
foreach ($Core in $Cores.status.PSObject.Properties)
{
    # Get the number of records within each core
    $CoreRecords = Invoke-RestMethod -Method Get -Uri ([string]::Format("{0}/{1}/select?q=*:*", $SolrUri, $Core.Name))

    # Check if the core has at least 1 record
    if ($CoreRecords.response.numFound -gt 0)
    {
        # Get all records from the core and save them to disk in the specified format
        Invoke-RestMethod -Method Get -Uri ([string]::Format("{0}/{1}/select?q=*:*&fl=*&ident=true&wt={2}&rows={3}", $SolrUri, $Core.Name, $Format, $CoreRecords.response.numFound)) -OutFile ([string]::Format("{0}\{1}-{2}-export.{3}", (Get-Location).Path, [DateTime]::Now.ToString("yyyyMMdd"), $Core.Name, $Format))
    }
}
