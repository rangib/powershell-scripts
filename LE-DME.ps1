[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)]
    [ValidateSet("Create","Delete")]
    [string]$Action,
    [Parameter(Mandatory,Position=1)]
    [string]$Identifier,
    [Parameter(Mandatory,Position=2)]
    [string]$Token,
    [Parameter(Mandatory,Position=3)]
    [string]$ApiKey,
    [Parameter(Mandatory,Position=4)]
    [string]$SecretKey,
    [Parameter(Mandatory,Position=5)]
    [ValidateSet("Live","Sandbox")]
    [string]$Mode
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

class Mode
{
    static [string] $Live = "Live";
    static [string] $Sandbox = "Sandbox";
}

class DME
{
    hidden [string] $Mode;
    hidden [string] $ApiKey;
    hidden [string] $SecretKey;
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] $BaseApiUrl;
    hidden [System.Collections.Hashtable] $DomainCache = [System.Collections.Hashtable]::new();

    DME([string] $Mode, [string] $ApiKey, [string] $SecretKey)
    {
        $this.Mode = $Mode;
        $this.ApiKey = $ApiKey;
        $this.SecretKey = $SecretKey;

		Write-Debug "Mode: $($this.Mode) Api Key: $($this.ApiKey) Secret Key: $($this.SecretKey -replace '\w','*')"

        $this.ConfigureBaseUrls();
    }

    hidden [void] ConfigureBaseUrls()
    {
        $this.BaseApiUrl = [System.Collections.Generic.Dictionary[[string],[string]]]::new();
        $this.BaseApiUrl.Add([Mode]::Live, "https://api.dnsmadeeasy.com/V2.0/dns/managed");
        $this.BaseApiUrl.Add([Mode]::Sandbox, "https://api.sandbox.dnsmadeeasy.com/V2.0/dns/managed");
    }
    
    hidden [System.Collections.Generic.Dictionary[[string],[string]]] GetDMEAuthHeader()
    {
        $secretKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($this.SecretKey);
        $hmac = [System.Security.Cryptography.HMACSHA1]::new($secretKeyBytes, $true);

        $requestDate = [System.DateTime]::UtcNow.ToString("r");
        $requestDateBytes = [System.Text.Encoding]::UTF8.GetBytes($requestDate);
        $requestDateHash = [System.BitConverter]::ToString($hmac.ComputeHash($requestDateBytes)).Replace("-", "").ToLower();

        $authHeaders = [System.Collections.Generic.Dictionary[[string],[string]]]::new();
        $authHeaders.Add("x-dnsme-hmac", $requestDateHash);
        $authHeaders.Add("x-dnsme-apiKey", $this.ApiKey);
        $authHeaders.Add("x-dnsme-requestDate", $requestDate);

        return $authHeaders;
    }

    hidden [System.Array] FindDMEZone([string] $domain)
    {
        if ($this.DomainCache.ContainsKey($domain))
        {
            return $this.DomainCache.$domain;
        }

        $apiUrl = $this.BaseApiUrl[$this.Mode];

        try
        {
            $authHeaders = $this.GetDMEAuthHeader();
            $response = Invoke-RestMethod -Method Get -Uri $apiUrl -Headers $authHeaders -ContentType "application/json";
            $zones = $response.data;
        }
        catch
        {
            throw;
        }

        $domainPieces = $domain.Split(".");

        for ($i = 0; $i -lt ($domainPieces.Count - 1); $i++)
        {
            $zoneQuery = "$($domainPieces[$i..($domainPieces.Count-1)] -join '.')";
            $zone = $zones | Where-Object { $_.name -eq $zoneQuery }
            
            if ($zone)
            {
                $this.DomainCache.$domain = $zone.id,$zone.name;

                return $zone.id,$zone.name;
            }                
        }

        return $null;
    }

    [void] CreateTxtRecord([string] $domain, [string] $token)
    {
		Write-Debug "Creating TXT record $($domain)"
	
        if (!($zoneId, $zoneName = $this.FindDMEZone($domain)))
        {
            throw "Unable to find DME hosted zone for $domain";
        }

        $recShort = $domain -ireplace [System.Text.RegularExpressions.Regex]::Escape(".$zoneName"), [string]::Empty;
        
        $apiUrl = "$($this.BaseApiUrl[$this.Mode])/$($zoneId)/records"

        try
        {
            $authHeaders = $this.GetDMEAuthHeader();
            $response = Invoke-RestMethod -Method Get -Uri "$($apiUrl)?recordName=$recShort&type=TXT" -Headers $authHeaders -ContentType "application/json";
        }
        catch
        {
            throw;
        }

        if ($response.totalRecords -gt 0)
        {
            if ("`"$token`"" -in $response.data.value) {
                Write-Debug "Domain $($domain) already contains $($token). Nothing to do";
                return;
            }
        }

        $postData = @{
            name=$recShort;
            value="`"$token`"";
            type="TXT";
            ttl=10;
        } | ConvertTo-Json -Compress;

        try
        {
            $authHeaders = $this.GetDMEAuthHeader();
            
            Invoke-RestMethod -Method Post -Uri $apiUrl -Headers $authHeaders -Body $postData -ContentType "application/json";
        }
        catch
        {
            throw;
        }
    }

    [void] DeleteTxtRecord([string] $domain, [string] $token)
    {
		Write-Debug "Removing TXT record $($domain)"
	
        if (!($zoneId, $zoneName = $this.FindDMEZone($domain)))
        {
            throw "Unable to find DME hosted zone for $domain";
        }

        $recShort = $domain -ireplace [System.Text.RegularExpressions.Regex]::Escape(".$zoneName"), [string]::Empty;
        
        $apiUrl = "$($this.BaseApiUrl[$this.Mode])/$($zoneId)/records"

        try
        {
            $authHeaders = $this.GetDMEAuthHeader();
            $response = Invoke-RestMethod -Method Get -Uri "$($apiUrl)?recordName=$recShort&type=TXT" -Headers $authHeaders -ContentType "application/json";
        }
        catch
        {
            throw;
        }

        if ($response.totalRecords -eq 0)
        {
            Write-Debug "Domain $($domain) doesn't exist. Nothing to do";
            return;
        }
        else
        {
            if ("`"$token`"" -notin $response.data.value)
            {
                Write-Debug "Domain $($domain) does not contain $($token). Nothing to do.";
            }

            $txtId = ($response.data | Where-Object { $_.value -eq "`"$token`"" }).id;

            try
            {
                $authHeaders = $this.GetDMEAuthHeader();
                $txtRecordUrl = "$($apiUrl)/$txtId";

                Invoke-RestMethod -Method Delete -Uri $txtRecordUrl -Headers $authHeaders -ContentType "application/json";
            }
            catch
            {
                throw;
            }
        }
    }
}

$DME = [DME]::new($Mode, $ApiKey, $SecretKey);

if ($Action -eq "Create")
{
    $DME.CreateTxtRecord($Identifier, $Token);
}

if ($Action -eq "Delete")
{
    $DME.DeleteTxtRecord($Identifier, $Token);
}