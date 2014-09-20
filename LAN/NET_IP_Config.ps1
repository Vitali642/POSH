# script parameters
param(
[Parameter(Position=0,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$true)]
[alias("Name","ComputerName")][string[]]$Computers = @($env:computername),
$Domain = "company.domain",
$DNSSuffix = @("company.domain,company.legacy.domain,company.com"),
$DNSServers = @("10.10.0.1", "10.12.1.1", "10.10.0.2", "10.12.1.2"),
$WINSServers = @("10.10.0.3", "10.12.1.3"),
$Gateway = @("10.10.255.254"),
[switch] $ChangeSettings,
[switch] $EnableDHCP,
[switch] $IpRelease, 
[switch] $BatchReport
)

process{
foreach ($Computer in $Computers){
	If (Test-connection $Computer -quiet -count 1 -EA stop){
		Try {
			[array]$NICs = (Get-WMIObject -Class Win32_NetworkAdapterConfiguration -Computername $Computer -Filter "IPEnabled = TRUE" -EA Stop)
			}
		Catch {
			Write-Warning "$($error[0])"
			Write-Output "$("INACCESSIBLE: ")$($nl)$($Computer)"
			Write-Host $nl
			continue
			}
		# Generate selection menu
		$NICindex = $NICs.count
		Write-Host "$nl Selection for $($Computer) : $nl"
		For ($i=0;$i -lt $NICindex; $i++) {
			Write-Host -ForegroundColor Green "$i --> $($NICs[$i].Description)"
			Write-Output $(ShowDetails $NICs[$i] $Computer)
			}
		$nl
		# if reporting only then skip menu + processing code
		if ($BatchReport){continue}
		Write-Host -ForegroundColor Green "q --> Quit" $nl
		# Wait for user selection input
		Do {
			$SelectIndex = Read-Host "Select connection by number or 'q' (=default) to quit"
			Switch -regex ($SelectIndex){
				"^q.*" 	{$SelectIndex="quit"; $kip = $true}
				"\d" 	{$SelectIndex = $SelectIndex -as [int];$kip = $false}
				"^\s*$" {$SelectIndex="quit"; $kip = $true}
			}
		}
		Until (($SelectIndex -lt $NICindex) -OR $SelectIndex -like "q*")
		$nl
		Write-Host "You selected: $SelectIndex" $nl
		#skip current $computer if $true
		If ($kip) {continue}
		Else {ProcessNIC $NICs[$SelectIndex] $Computer}
		}
	else {Write-warning "$Computer cannot be reached"}
	}#foreach
}#process

begin{
# script variables
$nl = [Environment]::NewLine

# script functions
Function ProcessNIC($NIC, $Computer){
	# Change settings for selected network card if option is true and show updated values
	If ($ChangeSettings){
		If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
			Write-Warning "You need Administrator rights to run this script!"
			Break
		}
		If ($IpRelease){
			#$NIC.ReleaseDHCPLease
			$NIC.RenewDHCPLease
			}
		Else{
			ChangeIPConfig $NIC $Computer
			}
			start-sleep -s 2
			Write-Host $nl "    ====NEW SETTINGS====" $nl
			$UpdatedNIC = Get-WMIObject -Class Win32_NetworkAdapterConfiguration -Computername $Computer -Filter "Index=$($NIC.Index)"
			Write-Output $(ShowDetails $UpdatedNIC $Computer)$($nl)
		}
	Else{
			$nl
			Write-Warning "For changing settings add -ChangeSettings as parameter, if not this script is output only"
			$nl
		}
}

Function ChangeIPConfig($NIC, $Computer){
	if ($EnableDHCP){
		$NIC.EnableDHCP()
		$NIC.SetDNSServerSearchOrder()
		}
	else{
		$DNSServers = Get-random $DNSservers -Count $DNSServers.Length
		$NIC.SetDNSServerSearchOrder($DNSServers) | Out-Null
		#$x = 0
		#$IPaddress = @()
		#$NetMask = @()
		#$Gateway = @()
		#$Metric = @()
		#foreach ($IP in $NIC.IPAddress){
			#$IPaddress[$x] = $NIC.IPAddress[$x]
			#$NetMask[$x] = $NIC.IPSubnet[$x]
			#$Gateway[$x] = $NIC.DefaultIPGateway[$x]
			#$Metric[$x] = $NIC.GatewayCostMetric[$x]
			#$x++
		#}
		#$NIC.EnableStatic($IPaddress, $NetMask)
		#$NIC.SetGateways($Gateway, $Metric)
		#$NIC.SetWINSServer($WINSServers)
		}
	$NIC.SetDynamicDNSRegistration("TRUE") | Out-Null
	$NIC.SetDNSDomain("") | Out-Null
	# remote WMI registry method for updating DNS Suffix SearchOrder
	$registry = [WMIClass]"\\$computer\root\default:StdRegProv"
	$HKLM = [UInt32] "0x80000002"
	$registry.SetStringValue($HKLM, "SYSTEM\CurrentControlSet\Services\TCPIP\Parameters", "SearchList", $DNSSuffix) | Out-Null
}

Function ShowDetails($NIC, $Computer){
	Write-Output "$($nl)$(" IP settings on: ")$($Computer)$($nl)$($nl)$(" for") $($NIC.Description)$(":")$($nl)"
	Write-Output "$("Hostname = ")$($NIC.DNSHostName)"
	Write-Output "$("DNSDomain= ")$($NIC.DNSDomain)"
	Write-Output "$("Domain DNS Registration Enabled = ")$($NIC.DomainDNSRegistrationEnabled)"
	Write-Output "$("Full DNS Registration Enabled = ")$($NIC.FullDNSRegistrationEnabled)"
	Write-Output "$("DNS Domain Suffix Search Order = ")$($NIC.DNSDomainSuffixSearchOrder)"
	Write-Output "$("MAC address = ")$($NIC.MACAddress)"
	Write-Output "$("DHCP enabled = ")$($NIC.DHCPEnabled)"
	# show all IP adresses on this NIC
	$x = 0
	foreach ($IP in $NIC.IPAddress){
		Write-Output "$("IP address $x =")$($NIC.IPAddress[$x])$("/")$($NIC.IPSubnet[$x])"
		$x++
	}
	Write-Output "$("Default IP Gateway = ")$($NIC.DefaultIPGateway)"
	Write-Output "$("DNS Server Search Order = ")$($NIC.DNSServerSearchOrder)"
}
}