ImportSystemModules

[void][System.Reflection.Assembly]::LoadWithPartialName('system.serviceprocess')

set-variable `
    -name itgPSServiceHost `
    -value ([System.IO.Path]::GetFullPath("$env:ProgramFiles\Windows Resource Kits\Tools\srvany.exe")) `
    -option constant

set-variable `
    -name itgPSServiceCmdLine `
    -value '"powershell.exe -NoExit -File `"$($File)`" -NoLogo -NonInteractive -WindowStyle Hidden"' `
    -option constant

set-variable `
    -name itgPSServiceStartupOptions `
    -value @{ `
        [System.ServiceProcess.ServiceStartMode]::Manual = "demand"; `
        [System.ServiceProcess.ServiceStartMode]::Automatic = "auto"; `
        [System.ServiceProcess.ServiceStartMode]::Disabled = "disabled" `
    } `
    -option constant

function New-PSService {
	<#
		.Synopsis
		    ����������� � ������� ����� ������, �������������� �� ���� �������� power shell.
		.Description
		    ����������� � ������� ����� ������, �������������� �� ���� �������� power shell. � �������� ���� �������� �����
            ����������� srvany.exe �� ������� RK. 
		.Parameter File
		    ���� � ����� �������, ������� � ������ �������
		.Parameter Name
			������������� (��������) ������
		.Parameter DisplayName
			������������ ������������� ������
		.Parameter Description
            �������� ������
        .Parameter Group
            ������ �����, � ������� ������ ���� �������� ������ ������
        .Parameter DependsOnServices
            ������ ��������������� �����, �� ������� ������� ������ ������
        .Parameter DependsOnGroups
            ������ ��������������� ����� ��������, �� ������� ������� ������ ������
        .Parameter StartupType
            ������� ������� ������
        .Parameter RestoreParams
            ��������� �������������� ������ � ������ ����
		.Example
			����������� ����� ������:
            
			New-PSService `
                -File "c:\windows\service.ps1" `
                -Name "NewService1" `
                -DisplayName "����� ������" `
                -DependsOnServices "SMTPSVC", "NetLogon" `
                -StartupType "Automatic" `
                -RestoreParams @{ `
                    reset=77; `
                    reboot="";
                    command="";
                    failureActions = `
                        @{action="restart";period=60}, `
                        @{action="restart";period=60}, `
                        @{action="restart";period=60} `
                }
	#>
    param (
		[Parameter(
			Mandatory=$true,
			Position=0,
			ValueFromPipeline=$false,
			HelpMessage="���� � ����� �������, ������� � ������ �������."
		)]
        [string]$File,
		[Parameter(
			Mandatory=$true,
			Position=1,
			ValueFromPipeline=$false,
			HelpMessage="������������� (��������) ������."
		)]
        [string]$Name,
		[Parameter(
			Mandatory=$false,
			Position=2,
			ValueFromPipeline=$false,
			HelpMessage="������������ ������������� ������."
		)]
  		[string]$DisplayName = $Name,
		[Parameter(
			Mandatory=$false,
			Position=3,
			ValueFromPipeline=$false,
			HelpMessage="�������� ������."
		)]
  		[string]$Description = "������ �� ���� �������� PowerShell $([System.IO.Path]::GetFileNameWithoutExtension($File))",
		[Parameter(
			Mandatory=$false,
			Position=4,
			ValueFromPipeline=$false,
			HelpMessage="������ �����, � ������� ������ ���� �������� ������ ������."
		)]
  		[string]$Group,
		[Parameter(
			Mandatory=$false,
			Position=5,
			ValueFromPipeline=$false,
			HelpMessage="������ ��������������� �����, �� ������� ������� ������ ������."
		)]
  		[string[]]$DependsOnServices,
		[Parameter(
			Mandatory=$false,
			Position=6,
			ValueFromPipeline=$false,
			HelpMessage="������ ��������������� ����� �����, �� ������� ������� ������ ������."
		)]
  		[string[]]$DependsOnGroups,
		[Parameter(
			Mandatory=$false,
			Position=7,
			ValueFromPipeline=$false,
			HelpMessage="������� ������� ������."
		)]
  		[System.ServiceProcess.ServiceStartMode]$StartupType = [System.ServiceProcess.ServiceStartMode]::Manual,
		[Parameter(
			Mandatory=$false,
			Position=8,
			ValueFromPipeline=$false,
			HelpMessage="��������� �������������� ������ � ������ ����."
		)]
  		$RestoreParams
	)

        # http://msdn.microsoft.com/en-us/library/bb490995.aspx
        [string[]]$depends = $null
        if ($DependsOnServices) {
            $depends += $DependsOnServices
        }
        if ($DependsOnGroups) {
            $depends += ($DependsOnGroups | %{ "+$_" })
        }
        ( `
            "sc.exe create " + `
                "$Name " + `
                "type= own " + `
                "start= $($itgPSServiceStartupOptions[$StartupType]) " + `
                "error= normal " + `
                "binPath= `"$($itgPSServiceHost)`" " + `
                "$(if ($Group) {'group= "' + $($Group) + '" '})" + `
                "$(if ($depends) {'depend= "' + ($depends -join ' ') + '" '})" + `
                "displayName= `"$($DisplayName)`" " `
        ) | invoke-expression | write-debug

        ( `
            "sc.exe config " + `
                "$Name " + `
                "type= own " + `
                "start= $($itgPSServiceStartupOptions[$StartupType]) " + `
                "error= normal " + `
                "binPath= `"$($itgPSServiceHost)`" " + `
                "$(if ($Group) {'group= "' + $($Group) + '" '})" + `
                "$(if ($depends) {'depend= "' + ($depends -join ' ') + '" '})" + `
                "displayName= `"$($DisplayName)`" " `
        ) | invoke-expression | write-debug

        ( `
            "sc.exe description " + `
                "$Name " + `
                "`"$($Description)`"" `
        ) | invoke-expression | write-debug

        New-Item `
            -path "HKLM:\SYSTEM\CurrentControlSet\services\$Name\Parameters" `
            -ErrorAction SilentlyContinue

        Set-ItemProperty `
            -path "HKLM:\SYSTEM\CurrentControlSet\services\$Name\Parameters" `
            -name "Application" `
            -value (invoke-expression $itgPSServiceCmdLine) `
            -force

        if ($RestoreParams) {
            if ($RestoreParams.reset -isnot [System.TimeSpan]) {
                $RestoreParams.reset = New-TimeSpan -days $RestoreParams.reset
            }
            $RestoreParams.failureActions | %{
                if ($_.period -isnot [System.TimeSpan]) {
                    $_.period = New-TimeSpan -minutes $_.period
                }
            }
            
            # http://msdn.microsoft.com/en-us/library/cc742019.aspx
            ( `
                "sc.exe failure " + `
                    "$Name " + `
                    "reset= $($RestoreParams.reset.TotalSeconds) " + `
                    "$(if ($RestoreParams.reboot) {'reboot= "' + $($RestoreParams.reboot) + '" '})" + `
                    "$(if ($RestoreParams.command) {'command= "' + $($RestoreParams.command) + '" '})" + `
                    "actions= $(($RestoreParams.failureActions | %{ "$($_.action)/$($_.period.TotalMilliseconds)" }) -join '/')" `
            ) | invoke-expression | write-debug
        }

        Get-Service -Name $Name | write-output
}  

Export-ModuleMember "New-PSService"
