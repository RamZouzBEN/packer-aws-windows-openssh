<powershell>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wrap {
    Param([scriptblock]$block)
    Write-Host "+ $($block.ToString().Trim())"
    try {
        Invoke-Command -ScriptBlock $block
    } catch {
        Write-Host "ERROR: $_"
    }
}

Start-Transcript -Path "C:\winrm.log" -Force

Write-Host "INIT"

Wrap { Disable-NetFirewallRule -DisplayGroup 'Windows Remote Management' }

# update network to Private
Wrap { New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" -Force | Out-Null }
Wrap { Set-NetConnectionProfile -InterfaceIndex (Get-NetConnectionProfile).InterfaceIndex -NetworkCategory Private }

Wrap {
    New-NetFirewallRule `
        -Name 'WINRM-HTTPS-In-TCP' `
        -DisplayName 'Windows Remote Management (HTTPS-In)' `
        -Description "Inbound rule for Windows Remote Management via WS-Management. [TCP 5986]" `
        -Group 'Windows Remote Management' `
        -Program 'System' `
        -Protocol TCP `
        -LocalPort 5986 `
        -Action 'Allow' `
        -Enabled False | Out-Null
}

# add HTTPS listeners
Wrap {
    $cert = New-SelfSignedCertificate -CertstoreLocation Cert:\LocalMachine\My -DnsName "packer"
    New-Item -Path WSMan:\LocalHost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Hostname "packer" -Port 5986 -Force | Out-Null
}

# tune winrm
Wrap { Set-Item -Path WSMan:\localhost\MaxTimeoutms -Value 180000 -Force }
Wrap { Set-Item -Path WSMan:\localhost\Client/TrustedHosts -Value * -Force }

# required for NTLM auth
Wrap { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -Value 2 -Type DWord -Force }
Wrap { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name 'NTLMMinServerSec' -Value 536870912 -Type DWord -Force }
Wrap { Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Force }

# keep service running
Wrap { Set-Service -Name WinRM -StartupType Automatic }
Wrap { Restart-Service -Name WinRM }

Wrap { Enable-NetFirewallRule -DisplayName 'Windows Remote Management (HTTPS-In)' }

# prepare artifacts storage
Wrap { New-Item -Path "C:\packer" -Type Directory -Force | Out-Null }
Wrap {
    $acl = Get-ACL "C:\packer"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("everyone","FullControl","ContainerInherit,Objectinherit","none","Allow")
    $acl.AddAccessRule($rule)
    Set-Acl -Path "C:\packer" -AclObject $acl
}

Write-Host "DONE"

Stop-Transcript

Wrap { Move-Item -Path "C:\winrm.log" -Destination "C:\packer\" -Force }
</powershell>