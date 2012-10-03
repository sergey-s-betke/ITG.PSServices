ImportSystemModules;

add-type -assembly 'System.ServiceProcess'; 

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
            Регистрация в реестре новой службы, представляющей из себя сценарий power shell.
        .Description
            Регистрация в реестре новой службы, представляющей из себя сценарий power shell. В качестве хост процесса будет
            использован srvany.exe из состава RK. 
        .Parameter File
            Путь к файлу скрипта, который и станет службой
        .Parameter Name
            Идентификатор (короткий) службы
        .Parameter DisplayName
            Отображаемый идентификатор службы
        .Parameter Description
            Описание службы
        .Parameter Group
            Группа служб, к которой должна быть отнесена данная служба
        .Parameter DependsOnServices
            Массив идентификаторов служб, от которых зависит данная служба
        .Parameter DependsOnGroups
            Массив идентификаторов групп сервисов, от которых зависит данная служба
        .Parameter StartupType
            Вариант запуска службы
        .Parameter RestoreParams
            Параметры восстановления службы в случае сбоя
		.Link
			# http://msdn.microsoft.com/en-us/library/bb490995.aspx
        .Example
            Регистрация новой службы:
            
            New-PSService `
                -File "c:\windows\service.ps1" `
                -Name "NewService1" `
                -DisplayName "Новый сервис" `
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
            HelpMessage="Путь к файлу скрипта, который и станет службой."
        )]
        [string]$File
	,
        [Parameter(
            Mandatory=$true,
            Position=1,
            ValueFromPipeline=$false,
            HelpMessage="Идентификатор (короткий) службы."
        )]
        [string]$Name
	,
        [Parameter(
            Mandatory=$false,
            Position=2,
            ValueFromPipeline=$false,
            HelpMessage="Отображаемый идентификатор службы."
        )]
        [string]$DisplayName = $Name
	,
        [Parameter(
            Mandatory=$false,
            Position=3,
            ValueFromPipeline=$false,
            HelpMessage="Описание службы."
        )]
        [string]$Description = "Служба на базе сценария PowerShell $([System.IO.Path]::GetFileNameWithoutExtension($File))"
	,
        [Parameter(
            Mandatory=$false,
            Position=4,
            ValueFromPipeline=$false,
            HelpMessage="Группа служб, к которой должна быть отнесена данная служба."
        )]
        [string]$Group
	,
        [Parameter(
            Mandatory=$false,
            Position=5,
            ValueFromPipeline=$false,
            HelpMessage="Массив идентификаторов служб, от которых зависит данная служба."
        )]
        [string[]]$DependsOnServices
	,
        [Parameter(
            Mandatory=$false,
            Position=6,
            ValueFromPipeline=$false,
            HelpMessage="Массив идентификаторов групп служб, от которых зависит данная служба."
        )]
        [string[]]$DependsOnGroups
	,
        [Parameter(
            Mandatory=$false,
            Position=7,
            ValueFromPipeline=$false,
            HelpMessage="Вариант запуска службы."
        )]
        [System.ServiceProcess.ServiceStartMode]$StartupType = [System.ServiceProcess.ServiceStartMode]::Manual
	,
        [Parameter(
            Mandatory=$false,
            Position=8,
            ValueFromPipeline=$false,
            HelpMessage="Параметры восстановления службы в случае сбоя."
        )]
        $RestoreParams
    )

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
