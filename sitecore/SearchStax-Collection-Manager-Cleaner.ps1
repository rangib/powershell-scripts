[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$AccountName,
    [Parameter(Mandatory=$true)]
    [string]$DeploymentUid,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password,
    [string]$SolrUsername = "",
    [string]$SolrPassword = ""
)

$Global:ProgressPreference = 'SilentlyContinue'

class SolrCollection
{
    hidden [string]$Name

    SolrCollection([string]$CollectionName)
    {
        $this.Name = $CollectionName
    }

    [string]GetName()
    {
        return $this.Name
    }
}

class SearchStaxProvider
{
    hidden [System.Collections.Generic.Dictionary[[string],[string]]]$AuthTokenHeaders = [System.Collections.Generic.Dictionary[[string],[string]]]::new()
    hidden [System.Collections.Generic.Dictionary[[string],[string]]]$AuthBasicHeaders = [System.Collections.Generic.Dictionary[[string],[string]]]::new()

    hidden [string]$AccountName
    hidden [string]$DeploymentUid
    hidden [string]$Username
    hidden [string]$Password
    hidden [string]$SitecoreVersion
    hidden [string]$SolrUsername
    hidden [string]$SolrPassword

    hidden [string]$BaseUrl = "https://app.searchstax.com"
    hidden [string]$AuthUrl = [string]::Format("{0}/api/rest/v2/obtain-auth-token/", $this.BaseUrl)
    hidden [string]$DeploymentUrl
    hidden [string]$ConfigListUrl
    hidden [string]$ConfigDeleteUrl

    hidden [string]$AliasListUrl = "{0}admin/collections?action=LISTALIASES&wt=json"
    hidden [string]$CollectionListUrl = "{0}admin/collections?action=LIST&wt=json"
    hidden [string]$DeleteCollectionUrl = "{0}admin/collections?action=DELETE&name={1}"
    hidden [string]$DeleteCollectionAliasUrl = "{0}admin/collections?action=DELETEALIAS&name={1}"

    SearchStaxProvider([string]$AccountName, [string]$DeploymentUid, [string]$Username, [string]$Password, [string]$SolrUsername, [string]$SolrPassword)
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

        $this.SetAuthBasicHeaders()
        $this.SetAuthTokenHeaders()
    }

    hidden [void]SetDeploymentUrl([string]$AccountName, [string]$DeploymentUid)
    {
        $this.DeploymentUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void]SetConfigListUrl([string]$AccountName, [string]$DeploymentUid)
    {
        $this.ConfigListUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/zookeeper-config/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void]SetConfigDeleteUrl([string]$AccountName, [string]$DeploymentUid)
    {
        $this.ConfigDeleteUrl = [string]::Format("{0}/api/rest/v2/account/{1}/deployment/{2}/zookeeper-config/", $this.BaseUrl, $AccountName, $DeploymentUid)
    }

    hidden [void]SetAuthBasicHeaders()
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

    hidden [void]SetAuthTokenHeaders()
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

    [bool]CheckIfDeploymentExists()
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

    hidden [object]GetDeploymentInfo()
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

    [string]GetDeploymentSolrUrl()
    {
        $Info = $this.GetDeploymentInfo()

        if ($Info -ne $null)
        {
            return $Info.http_endpoint
        }

        return [string]::Empty
    }

    [System.Collections.Generic.List[[string]]]GetRemoteCollectionAliases()
    {
        Write-Host "Retrieving list of collection aliases ... " -NoNewline

        $Aliases = [System.Collections.Generic.List[[string]]]::new()

        try
        {
            $Result = Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.AliasListUrl, $this.GetDeploymentSolrUrl()))

            if ([bool]$Result.PSObject.Properties.name -contains "aliases")
            {
                foreach ($Alias in $Result.aliases.PSObject.Properties)
                {
                    $Aliases.Add($Alias.Name)
                }
            }

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }

        return $Aliases
    }

    [void]RemoveRemoteCollectionAlias([string]$CollectionAlias, [string]$Message)
    {
        Write-Host $Message -NoNewline

        try
        {
            Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.DeleteCollectionAliasUrl, $this.GetDeploymentSolrUrl(), $CollectionAlias))

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }
    }

    [System.Collections.Generic.List[[string]]]GetRemoteCollections()
    {
        Write-Host "Retrieving list of collections ... " -NoNewline

        $Collections = [System.Collections.Generic.List[[string]]]::new()

        try
        {
            $Result = Invoke-RestMethod -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.CollectionListUrl, $this.GetDeploymentSolrUrl()))

            if ([bool]$Result.PSObject.Properties.name -contains "collections")
            {
                foreach ($Collection in $Result.collections)
                {
                    $Collections.Add($Collection) | Out-Null
                }
            }

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }

        return $Collections
    }

	[void]RemoveRemoteCollection([string]$CollectionName, [string]$Message)
	{
        $Result = $false

        Write-Host $Message -NoNewline

        try
        {
            $Response = Invoke-WebRequest -Method Get -Headers $this.AuthBasicHeaders -Uri ([string]::Format($this.DeleteCollectionUrl, $this.GetDeploymentSolrUrl(), $CollectionName))
            
            $Result = ($Response.StatusCode -eq 200)
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
	}

    [System.Collections.Generic.List[[string]]]GetRemoteConfigs()
    {
        Write-Host "Retrieving list of configs ... " -NoNewline

        $Configs = [System.Collections.Generic.List[[string]]]::new()

        try
        {
            $Result = Invoke-RestMethod -Method Get -Headers $this.AuthTokenHeaders -Uri $this.ConfigListUrl

            if ([bool]$Result.PSObject.Properties.name -contains "configs")
            {
                foreach ($Config in $Result.configs)
                {
                    $Configs.Add($Config) | Out-Null
                }
            }

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }

        return $Configs
    }

    [void]RemoveRemoteConfigSet([string]$CollectionName, [string]$Message)
    {
        $Result = $false

        Write-Host $Message -NoNewline

        try
        {
            $Response = Invoke-WebRequest -Method Delete -Headers $this.AuthTokenHeaders -Uri ([string]::Format("{0}{1}/", $this.ConfigDeleteUrl, $CollectionName))
            
            $Result = ($Response.StatusCode -eq 200)
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

    }

}

class SearchStaxCollectionManager
{
    hidden [SearchStaxProvider]$SearchStaxProvider

    SearchStaxCollectionManager()
    {
    }

    SearchStaxCollectionManager([string]$AccountName, [string]$DeploymentUid, [string]$Username, [string]$Password, [string]$SolrUsername, [string]$SolrPassword)
    {
        $this.SearchStaxProvider = [SearchStaxProvider]::new($AccountName.Trim(), $DeploymentUid.Trim(), $Username.Trim(), $Password.Trim(), $SolrUsername.Trim(), $SolrPassword.Trim())
    }

    [void]Execute()
    {
        if (!$this.SearchStaxProvider.CheckIfDeploymentExists())
        {
            Write-Error -Message "Cannot find a deployment with the provided UID" -ErrorAction Stop
        }

		$CollectionAliases = $this.SearchStaxProvider.GetRemoteCollectionAliases()
        $Collections = $this.SearchStaxProvider.GetRemoteCollections()
        $Configs = $this.SearchStaxProvider.GetRemoteConfigs()

        if ($CollectionAliases.Count -gt 0)
        {
            foreach ($CollectionAlias in $CollectionAliases)
            {
                $this.SearchStaxProvider.RemoveRemoteCollectionAlias($CollectionAlias, ([string]::Format("Attempting to remove remote collection alias {0} ... ", $CollectionAlias)))
            }
        }
        else
        {
            Write-Host "No aliases need to be removed"
        }

        if ($Collections.Count -gt 0)
        {
            foreach ($Collection in $Collections)
            {
                $this.SearchStaxProvider.RemoveRemoteCollection($Collection, ([string]::Format("Attempting to remove remote collection {0} ... ", $Collection)))
            }
        }
        else
        {
            Write-Host "No collections need to be removed"
        }

        if ($Configs.Count -gt 0)
        {
            foreach ($Config in $Configs)
            {
                $this.SearchStaxProvider.RemoveRemoteConfigSet($Config, ([string]::Format("Attempting to remove remote config set {0} ... ", $Config)))
            }
        }
        else
        {
            Write-Host "No configs need to be removed"
        }
    }
}

$SearchStaxCollectionManager = [SearchStaxCollectionManager]::new($AccountName, $DeploymentUid, $Username, $Password, $SolrUsername, $SolrPassword)
$SearchStaxCollectionManager.Execute()