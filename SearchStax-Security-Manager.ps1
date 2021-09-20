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
    [bool]$Remove = $false,
    [string]$IpAddress,
    [System.Collections.ArrayList]$Services,
    [string]$Description
)

$Global:ProgressPreference = 'SilentlyContinue'

class SearchStaxSecurityProvider
{
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $AuthTokenHeaders = [System.Collections.Generic.Dictionary[[string],[string]]]::new()

    hidden [string] $AccountName
    hidden [string] $DeploymentUid
    hidden [string] $Username
    hidden [string] $Password

    hidden [string]$BaseUrl = "https://app.searchstax.com"
    hidden [string]$AuthUrl = [string]::Format("{0}/api/rest/v2/obtain-auth-token/", $this.BaseUrl)

    hidden [string] $AddCidrAddressUrl = "https://app.searchstax.com/api/rest/v2/account/{AccountName}/deployment/{DeploymentId}/ip-filter/add-cidr-ip/"
    hidden [string] $DelCidrAddressUrl = "https://app.searchstax.com/api/rest/v2/account/{AccountName}/deployment/{DeploymentId}/ip-filter/delete-cidr-ip/"

    SearchStaxSecurityProvider([string] $AccountName, [string] $DeploymentUid, [string] $Username, [string] $Password)
    {
        $this.AccountName = $AccountName
        $this.DeploymentUid = $DeploymentUid
        $this.Username = $Username
        $this.Password = $Password

        $this.SetAuthTokenHeaders()
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

    [void] AllowIp([string] $ipAddress, [System.Collections.ArrayList] $endpoints, [string] $description)
    {
        Write-Host "Allowing IP address $($ipAddress) ... " -NoNewline

        $Url = $this.AddCidrAddressUrl.Replace("{AccountName}", $this.AccountName).Replace("{DeploymentId}", $this.DeploymentUid)

        $RequestBody = @{
            cidr_ip=$ipAddress;
            services=$endpoints;
            description=$description;
        }

        $RequestBody = $RequestBody | ConvertTo-Json

        try
        {
            Invoke-RestMethod -Method Post -Uri $Url -Headers $this.AuthTokenHeaders -ContentType "application/json" -Body $RequestBody

            Write-Host "Done"
        }
        catch
        {
            Write-Verbose -Message $_

            Write-Host "Failed"
        }
    }

    [void] DisallowIp([string] $ipAddress)
    {
        Write-Host "Disallowing IP address $($ipAddress) ... " -NoNewline

        $Url = $this.DelCidrAddressUrl.Replace("{AccountName}", $this.AccountName).Replace("{DeploymentId}", $this.DeploymentUid)

        $RequestBody = @{
            cidr_ip=$ipAddress;
        }

        $RequestBody = $RequestBody | ConvertTo-Json

        try
        {
            Invoke-RestMethod -Method Post -Uri $Url -Headers $this.AuthTokenHeaders -ContentType "application/json" -Body $RequestBody

            Write-Host "Done"
        }
        catch
        {
            Write-Host "Failed"
        }
    }

}

class SearchStaxSecurityManager
{
    hidden [SearchStaxSecurityProvider] $SearchStaxSecurityProvider

    SearchStaxSecurityManager()
    {
    }

    SearchStaxSecurityManager([string] $AccountName, [string] $DeploymentUid, [string] $Username, [string] $Password)
    {
        $this.SearchStaxSecurityProvider = [SearchStaxSecurityProvider]::new($AccountName.Trim(), $DeploymentUid.Trim(), $Username.Trim(), $Password.Trim())
    }

    [void] AddIpAddress([string] $IpAddress, [System.Collections.ArrayList] $Services, [string] $Description)
    {
        if ([string]::IsNullOrEmpty($IpAddress))
        {
            $IpAddress = (Invoke-WebRequest -Uri https://ifconfig.me/ip).Content.Trim()
        }

        if ($null -eq $Services)
        {
            $Services = [System.Collections.ArrayList]@("solr","zk")
        }

        if ([string]::IsNullOrEmpty($Description))
        {
            $Description = "Added by $($this.GetType())"
        }

        $this.SearchStaxSecurityProvider.AllowIp($IpAddress, $Services, $Description)
    }

    [void] RemoveIpAddress([string] $IpAddress)
    {
        if ([string]::IsNullOrEmpty($IpAddress))
        {
            $IpAddress = (Invoke-WebRequest -Uri https://ifconfig.me/ip).Content.Trim()
        }

        $this.SearchStaxSecurityProvider.DisallowIp($IpAddress)
    }
}

$SearchStaxSecurityManager = [SearchStaxSecurityManager]::new($AccountName, $DeploymentUid, $Username, $Password)

if ($Remove)
{
    $SearchStaxSecurityManager.RemoveIpAddress($IpAddress)
}
else
{
    $SearchStaxSecurityManager.AddIpAddress($IpAddress, $Services, $Description)
}