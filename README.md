# AD Bulk User Onboarding

## The problem
Onboarding new hires one at a time in Active Directory Users and Computers is slow, repetitive, and error prone. Typos in usernames, missed attribute fields, and inconsistent password handling add up fast when HR hands you a spreadsheet of 20 new starters.

## What this script does
`New-ADUserBulkOnboarding.ps1` reads new-hire records from a CSV file and creates one Active Directory account per row:

- Generates unique `sAMAccountName` values automatically (appends a number on collisions)
- Sets a random 14-character temporary password that must be changed at first logon
- Places accounts in the OU from the CSV, or defaults to the domain Users container
- Optionally assigns a manager from the CSV
- Supports `-WhatIf` for safe dry runs before touching production
- Writes a per-row result log (created, skipped, failed) to CSV

## Requirements
- Windows PowerShell 5.1 or later
- RSAT Active Directory module (`Import-Module ActiveDirectory`)
- An account with rights to create users in the target OU

## How to run
Your CSV needs these headers (OU and Manager are optional):

```csv
FirstName,LastName,Department,Title,OU,Manager
Jane,Doe,IT,Help Desk Tech,,
```

Dry run first, then run for real:

```powershell
.\New-ADUserBulkOnboarding.ps1 -CsvPath .\newhires.csv -Domain contoso.com -WhatIf
.\New-ADUserBulkOnboarding.ps1 -CsvPath .\newhires.csv -Domain contoso.com
```

Replace `contoso.com` with your own domain.

## Security note
Temporary passwords are displayed on screen only. Distribute them through your password manager, never by email.

Written by Nicholas Shell. Part of a freelance IT automation portfolio.
