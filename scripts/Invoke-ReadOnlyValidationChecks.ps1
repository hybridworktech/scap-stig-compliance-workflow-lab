$ErrorActionPreference = "Continue"

$checks = @()

$checks += [pscustomobject]@{
    CheckName = "Firewall profiles visible"
    Command   = "Get-NetFirewallProfile"
    Status    = if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
    Note      = "Read-only check. Does not change firewall settings."
}

$checks += [pscustomobject]@{
    CheckName = "Local users visible"
    Command   = "Get-LocalUser"
    Status    = if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
    Note      = "Read-only inventory check. Does not modify accounts."
}

$checks += [pscustomobject]@{
    CheckName = "Audit policy command visible"
    Command   = "auditpol.exe"
    Status    = if (Get-Command auditpol.exe -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
    Note      = "Read-only availability check. Use explicit auditpol queries for evidence capture."
}

$checks += [pscustomobject]@{
    CheckName = "BitLocker command visible"
    Command   = "Get-BitLockerVolume"
    Status    = if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
    Note      = "Read-only availability check. Does not change encryption state."
}

$checks | Format-Table -AutoSize

