# Call this from inside a startup task/batch file as shown in the next two lines (minus the '# ')
# PowerShell -ExecutionPolicy Unrestricted .\HardenSsl.ps1 >> log-HardenSsl.txt 2>&1
# EXIT /B 0

# Credits: 
# http://azure.microsoft.com/blog/2014/10/19/how-to-disable-ssl-3-0-in-azure-websites-roles-and-virtual-machines/
# http://lukieb.blogspot.com/2014/11/tightening-up-your-azure-cloud-service.html

$nl = [Environment]::NewLine
$regkeys = @(
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client",
"HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server",
"HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002"
)

######################################################################################
#    CIPHER SUITE CONFIGURATION
#
# Redone in 2015 per http://security.stackexchange.com/questions/76993/now-that-it-is-2015-what-ssl-tls-cipher-suites-should-be-used-in-a-high-securit
# Plus
#  + added P521 for certain ECDHE + AES256 modes
#  + need to add _P256 etc at the end of TLS_ECDHE_*** ciphersuites for Windows/SCHANNEL format
$cipherorder ="" +
# TLS 1.2 AEAD only (all are SHA-2 as well)
"TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384_P521," +
"TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384_P384," +
"TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384_P256," +
"TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256_P384," + #  this is a TLS 1.2 "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-3
"TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256_P256," + #  this is a TLS 1.2 "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-3
"TLS_DHE_RSA_WITH_AES_256_GCM_SHA384," +
"TLS_DHE_RSA_WITH_AES_128_GCM_SHA256," +
"TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384_P521," + # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384_P384," + # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384_P256," + # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256_P384," + # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256_P256," + # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5

# TLS 1.2 SHA2 family
"TLS_DHE_RSA_WITH_AES_256_CBC_SHA256," + 
"TLS_DHE_RSA_WITH_AES_128_CBC_SHA256," + 
"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384_P521," + 
"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384_P384," + 
"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384_P256," + 
"TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256_P384," +   # this is a TLS 1.2 "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-3
"TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256_P256," +   # this is a TLS 1.2 "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-3
"TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384_P384," +  # this is a TLS 1.2 "may" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384_P256," +  # this is a TLS 1.2 "may" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256_P384," +  # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5
"TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256_P256," +  # this is a TLS 1.2 "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-5

# TLS 1.0 and 1.1 with modern ciphers (and outdated hashes, since that's all that's available)
"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA_P521," +    # this is a "may" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA_P384," +    # this is a "may" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA_P256," +    # this is a "may" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA_P384," +    # this is a "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA_P256," +    # this is a "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_DHE_RSA_WITH_AES_256_CBC_SHA," + 
"TLS_DHE_RSA_WITH_AES_128_CBC_SHA," + 

# TLS 1.0 and 1.1 with older but still reasonable ciphers and outdated hashes
# IE 8 on Windows XP is still out of luck, as is Java 6u45 due to DH parameter maximums.
"TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA," + 
"TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA_P384," +   # this is a "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA_P256," +   # this is a "should" category cipher suite for servers using RSA private keys and RSA certificates per NIST SP800-52 revision 1 table 3-2
"TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA_P384," +  # this is a "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-4
"TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA_P256," +  # this is a "should" category cipher suite for servers using elliptic curve private keys and ECDSA certificates per NIST SP800-52 revision 1 table 3-4

# For compatibility
"TLS_RSA_WITH_AES_128_CBC_SHA256," +
"TLS_RSA_WITH_AES_128_CBC_SHA," +
"TLS_RSA_WITH_AES_256_CBC_SHA256," +
"TLS_RSA_WITH_AES_256_CBC_SHA"
######################################################################################


# If any settings are changed, this will change to $True and the server will reboot
$reboot = $False
	
Function Set-CryptoSetting {
  param (
    $keyindex,
    $value,
    $valuedata,
    $valuetype,
    $restart
  )

    # For printing to console
    $regKey = $regkeys[$keyindex]
	
	# Check for existence of registry key, and create if it does not exist
	If (!(Test-Path -Path $regKey)) {		
		Write-Host "Creating key: $regKey$nl"		
		New-Item $regKey | Out-Null
	}

	If($value -eq $null){
		return $restart
	}

	# Get data of registry value, or null if it does not exist
	$val = (Get-ItemProperty -Path $regKey -Name $value -ErrorAction SilentlyContinue).$value

	If ($val -eq $null) {
		# Value does not exist - create and set to desired value
		Write-Host "Value $regKey\$value does not exist, creating...$nl"
		New-ItemProperty -Path $regKey -Name $value -Value $valuedata -PropertyType $valuetype | Out-Null
		$restart = $True
	} Else {
		# Value does exist - if not equal to desired value, change it
		If ($val -ne $valuedata) {
		  Write-Host "Value $regKey\$value not correct, setting it$nl"
		  Set-ItemProperty -Path $regKey -Name $value -Value $valuedata
		  $restart = $True
		}
		Else
		{
			Write-Host "Value $regKey\$value already set correctly$nl"
		}
	}
	return $restart
}

# Special function that can handle keys that have a forward slash in them. Powershell changes the forward slash
# to a backslash in any function that takes a path.
Function Set-CryptoKey {
 param (
  $parent,
  $childkey,
  $value,
  $valuedata,
  $valuetype,
  $restart
 )

	$child = $parent.OpenSubKey($childkey, $true);

	If ($child -eq $null) {
		# Need to create child key
		$child = $parent.CreateSubKey($childkey);
	}

	# Get data of registry value, or null if it does not exist
	$val = $child.GetValue($value);

	If ($val -eq $null) {
		# Value does not exist - create and set to desired value
		Write-Host "Value $child\$value does not exist, creating...$nl"
		$child.SetValue($value, $valuedata, $valuetype);
		$restart = $True
	} Else {
		# Value does exist - if not equal to desired value, change it
		If ($val -ne $valuedata) {
			Write-Host "Value $child\$value not correct, setting it$nl"
			$child.SetValue($value, $valuedata, $valuetype);
			$restart = $True
		}
		Else
		{
			Write-Host "Value $child\$value already set correctly$nl"
		}
	}

	return $restart
}

# Ensure TLS 1.2 parent folder exists
$reboot = Set-CryptoSetting 6 $null $null $null $reboot

# Ensure TLS 1.2 enabled for client
$reboot = Set-CryptoSetting 7 DisabledByDefault 0 DWord $reboot
$reboot = Set-CryptoSetting 7 Enabled 1 DWord $reboot

# Ensure TLS 1.2 enabled for server
$reboot = Set-CryptoSetting 8 Enabled 1 DWord $reboot
$reboot = Set-CryptoSetting 8 DisabledByDefault 0 DWord $reboot

# Ensure SSL 2.0 parent folder exists
$reboot = Set-CryptoSetting 9 $null $null $null $reboot

# Ensure SSL 2.0 disabled for client
$reboot = Set-CryptoSetting 10 DisabledByDefault 1 DWord $reboot

# Ensure SSL 2.0 disabled for server
$reboot = Set-CryptoSetting 11 Enabled 0 DWord $reboot

# Ensure SSL 3.0 parent folder exists
$reboot = Set-CryptoSetting 12 $null $null $null $reboot

# Ensure SSL 3.0 disabled for client
$reboot = Set-CryptoSetting 13 DisabledByDefault 1 DWord $reboot

# Ensure SSL 3.0 disabled for server
$reboot = Set-CryptoSetting 14 Enabled 0 DWord $reboot

# Set cipher priority
$reboot = Set-CryptoSetting 15 Functions $cipherorder String $reboot

# We have to do something special with these keys if they contain a forward-slash since
# Powershell converts the forward slash to a backslash and it screws up the creation of the key!
#
# Just create these parent level keys first
$cipherskey = (get-item HKLM:\).OpenSubKey("SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers",$true)
If ($cipherskey -eq $null) {
	$cipherskey = (get-item HKLM:\).CreateSubKey("SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers")
}

$hasheskey = (get-item HKLM:\).OpenSubKey("SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes",$true)
If ($hasheskey -eq $null) {
	$hasheskey = (get-item HKLM:\).CreateSubKey("SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes")
}

# Then add sub keys using a different function
# Disable RC4, DES, EXPORT, eNULL, aNULL, PSK and aECDH
# Details at https://support.microsoft.com/en-us/kb/245030

$reboot = Set-CryptoKey $cipherskey "RC4 128/128" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "Triple DES 168" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "RC2 128/128" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "RC4 64/128" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "RC4 56/128" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "RC2 56/128" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "DES 56" Enabled 0 DWord $reboot  # It's not clear whether the key is DES 56 or DES 56/56
$reboot = Set-CryptoKey $cipherskey "DES 56/56" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "RC4 40/128" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $cipherskey "RC2 40/128" Enabled 0 DWord $reboot

# Disable MD5, enable SHA (which should be by default)
$reboot = Set-CryptoKey $hasheskey "MD5" Enabled 0 DWord $reboot
$reboot = Set-CryptoKey $hasheskey "SHA" Enabled 0xFFFFFFFF DWord $reboot

$cipherskey.Close();
$hasheskey.Close();


# If any settings were changed, reboot
If ($reboot) {
	Write-Host "Rebooting now..."
	# shutdown: restart, in 5 sec, human readable reason/comment, force (running apps to close),
	#           machine readable reason (planned, 2:4 as reason)
	shutdown.exe /r /t 5 /c "Crypto settings changed" /f /d p:2:4
}
