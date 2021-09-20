[CmdletBinding()]

param(
    [Parameter(Mandatory=$true)]
    [string]$RootCertificateAuthorityName,
    [bool]$GenerateRootCertificate = $false,
    [Parameter(Mandatory=$true)]
    [string]$Domain,
    [Parameter(Mandatory=$true)]
    [string]$CertExportPath,
	[Parameter(Mandatory=$true)]
	[string]$CertPassword,
	[bool]$RootCertOnly = $false
)

if ([string]::IsNullOrEmpty($RootCertificateAuthorityName)) {
    Write-Error "You must provide a root CA name!"
    Exit 1
}

if ([string]::IsNullOrEmpty($Domain)) {
    Write-Error "You must provide a domain!"
    Exit 1
}

if ([string]::IsNullOrEmpty($CertPassword)) {
    Write-Error "You must provide a certificate export password!"
    Exit 1
}

if ([string]::IsNullOrEmpty($CertExportPath)) {
    Write-Error "You must provide a path to export your certificates!"
    Exit 1
}

if (![System.IO.Directory]::Exists($CertExportPath)) {
    Write-Error "Certificate export path does not exist!"
    Exit 1
}

$params = @{
  DnsName = $RootCertificateAuthorityName
  Subject = $RootCertificateAuthorityName
  KeyLength = 2048
  KeyAlgorithm = 'RSA'
  HashAlgorithm = 'SHA256'
  KeyExportPolicy = 'Exportable'
  NotAfter = (Get-Date).AddYears(50)
  CertStoreLocation = 'Cert:\LocalMachine\My'
  KeyUsage = 'CertSign','CRLSign' #fixes invalid cert error
}

$SecureCertPassword = $CertPassword | ConvertTo-SecureString -AsPlainText -Force

if ($GenerateRootCertificate) {

    $rootCA = New-SelfSignedCertificate @params
    $rootCAPath = [System.IO.Path]::Combine($CertExportPath, "$($RootCertificateAuthorityName).pfx")

    Export-PfxCertificate -Cert $rootCA -FilePath $rootCAPath -ChainOption BuildChain -Password $SecureCertPassword | Out-Null
    Import-PfxCertificate -Exportable -CertStoreLocation 'Cert:\LocalMachine\Root' -FilePath $rootCAPath -Password $SecureCertPassword | Out-Null

} else {
    $rootCA = (Get-ChildItem -Path Cert:\LocalMachine\Root -Recurse | Where-Object { $_.Subject -like "*CN=$($RootCertificateAuthorityName)*" })
}

if (!$RootCertOnly) {

	$params = @{
	  DnsName = $Domain
	  Subject = $Domain
	  Signer = $rootCA
	  KeyLength = 2048
	  KeyAlgorithm = 'RSA'
	  HashAlgorithm = 'SHA256'
	  KeyExportPolicy = 'Exportable'
	  NotAfter = (Get-date).AddYears(10)
	  CertStoreLocation = 'Cert:\LocalMachine\My'
	}

	$WildcardCert = New-SelfSignedCertificate @params
	$WildcardCertPath = [System.IO.Path]::Combine($CertExportPath, "$($Domain.Replace('*','_')).pfx")

	Export-PfxCertificate -Cert $WildcardCert -FilePath $WildcardCertPath -ChainOption BuildChain -Password $SecureCertPassword | Out-Null

	Remove-Item -Path "Cert:\LocalMachine\My\$($rootCA.Thumbprint)" -DeleteKey
	
}