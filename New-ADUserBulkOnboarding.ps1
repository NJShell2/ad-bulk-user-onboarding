<#
.SYNOPSIS
    Bulk-creates Active Directory user accounts from a CSV file.

.DESCRIPTION
    Reads new-hire records from a CSV and creates one AD account per row.
    Generates unique sAMAccountNames, sets a temporary password the user
    must change at first logon, writes a result log, and supports -WhatIf
    for safe dry runs.

    Expected CSV headers:
        FirstName, LastName, Department, Title, OU, Manager
    OU and Manager are optional (defaults to the domain's Users container).

    NOTE: Temporary passwords are shown on screen only. In production,
    distribute them through your password manager - never email them.

.EXAMPLE
    .\New-ADUserBulkOnboarding.ps1 -CsvPath .\newhires.csv -Domain contoso.com -WhatIf

.EXAMPLE
    .\New-ADUserBulkOnboarding.ps1 -CsvPath .\newhires.csv -Domain contoso.com
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$Domain,   # e.g. contoso.com (placeholder - use your own domain)

    [string]$LogPath = ".\OnboardingLog_$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

Import-Module ActiveDirectory -ErrorAction Stop

function New-RandomPassword {
    # 14 characters satisfying typical AD complexity requirements
    $chars = [char[]]'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*'
    -join (1..14 | ForEach-Object { $chars | Get-Random })
}

function Get-UniqueSamAccountName {
    param([string]$Base)
    $candidate = $Base
    $i = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $i++
        $candidate = "$Base$i"
    }
    return $candidate
}

function Get-DefaultUsersOU {
    param([string]$Domain)
    "CN=Users,$('DC=' + ($Domain -split '\.' -join ',DC='))"
}

$results  = @()
$rows     = Import-Csv -Path $CsvPath
$rowCount = 0

foreach ($row in $rows) {
    $rowCount++
    $result = [pscustomobject]@{
        Row            = $rowCount
        Name           = "$($row.FirstName) $($row.LastName)".Trim()
        SamAccountName = ''
        Status         = ''
        Detail         = ''
    }

    if (-not $row.FirstName -or -not $row.LastName) {
        $result.Status = 'Skipped'
        $result.Detail = 'Missing FirstName or LastName'
        $results += $result
        continue
    }

    $baseSam = ("{0}{1}" -f $row.FirstName.Substring(0, 1), $row.LastName) -replace '[^a-zA-Z0-9]', ''
    $sam     = (Get-UniqueSamAccountName -Base $baseSam).ToLower()
    $result.SamAccountName = $sam

    $upn      = "$sam@$Domain"
    $securePw = ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force
    $ou       = if ($row.OU) { $row.OU } else { Get-DefaultUsersOU -Domain $Domain }

    $newUserParams = @{
        Name                  = "$($row.FirstName) $($row.LastName)"
        GivenName             = $row.FirstName
        Surname               = $row.LastName
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        Path                  = $ou
        Department            = $row.Department
        Title                 = $row.Title
        AccountPassword       = $securePw
        Enabled               = $true
        ChangePasswordAtLogon = $true
    }
    if ($row.Manager) { $newUserParams['Manager'] = $row.Manager }

    try {
        if ($PSCmdlet.ShouldProcess($upn, 'Create AD user')) {
            New-ADUser @newUserParams -ErrorAction Stop
            $result.Status = 'Created'
            $result.Detail = 'Account created; temp password must be distributed securely'
        }
        else {
            $result.Status = 'WhatIf'
            $result.Detail = 'Dry run - no changes made'
        }
    }
    catch {
        $result.Status = 'Failed'
        $result.Detail = $_.Exception.Message
    }

    $results += $result
}

$results | Export-Csv -Path $LogPath -NoTypeInformation

$created = @($results | Where-Object { $_.Status -eq 'Created' }).Count
$failed  = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
Write-Host "Done: $created created, $failed failed, out of $($rows.Count) rows. Log: $LogPath" -ForegroundColor Green
