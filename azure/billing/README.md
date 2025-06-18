# Azure Cost Report Script – Installation & Setup Guide

This guide walks you through installing prerequisites, configuring access, and automating **`azure‑cost‑report.ps1`** so you can regenerate hosting‑cost reports on demand or on a schedule.

---

## 1&nbsp; Install PowerShell 7

```powershell
winget install --id Microsoft.Powershell --source winget
# – or –
# download the MSI from https://aka.ms/powershell-release
```

Verify the installation:

```powershell
pwsh -NoLogo -Command '$PSVersionTable.PSVersion'
```

PowerShell 7.2 + is recommended.

---

## 2&nbsp; Install the **Az** PowerShell module (v14 +)

```powershell
# inside pwsh
Install-Module Az -Repository PSGallery -Scope CurrentUser -Force
Get-InstalledModule Az
```

Az 14 bundles **Az.CostManagement 3.x** which exposes `Invoke-AzCostManagementQuery`.

---

## 3&nbsp; Sign in & select the subscription

```powershell
Connect-AzAccount
Select-AzSubscription -SubscriptionId <your-sub-GUID>
```

> The identity that runs the script must have **Cost Management Reader** (or higher) on the subscription.

---

## 4&nbsp; Place and customise the script

1. Download and save **`azure-cost-report.ps1`** (e.g. in `C:\Scripts\Billing`).
2. Change into the folder that you saved **`azure-cost-report.ps1`**

```powershell
pwsh .\azure-cost-report.ps1 `
     -Mode Tags -TagName Website -TagValues SiteA,SiteB,SiteC `
     -SubscriptionId 1111-2222-3333-4444 `
     -Currency AUD `
     -ReportPath C:\Reports\cost-$(Get-Date -f yyyyMMdd).md
```

---

## 5&nbsp; Tag or group your resources

| Mode | One‑time preparation |
|------|----------------------|
| **ResourceGroups** | Move every component the site needs into one RG per site (`rg-siteA`, `rg-siteB`, …). |
| **Tags** | Apply a common tag such as `Website = SiteA` to every related resource. Bulk‑tag in the portal or run:<br>`Update-AzTag -ResourceId <id> -Tag @{Website='SiteA'} -Operation Merge` |

---

## 6&nbsp; Run a manual smoke‑test

```powershell
pwsh .\azure-cost-report.ps1 `
     -Mode ResourceIds `
     -ResourceIds <arm-id1>,<arm-id2>,<arm-id3> `
     -SubscriptionId <guid> `
     -Months 12
```

Expected console output:

```
✅ Report written to C:\Scripts\Billingzure-hosting-cost-report.md
```

Open the Markdown file to confirm **Actual cost, Average per month, Forecast, and Budgets** are present.

---

## 7&nbsp; Automate it

| Host | Steps |
|------|-------|
| **Windows Task Scheduler** | 1. *Action*: `pwsh -File "C:\Scripts\Billing\azure-cost-report.ps1" …`<br>2. *Trigger*: monthly (e.g. 1st of each month at 09:00).<br>3. Tick **“Run whether user is logged on or not”** so cached Az credentials load. |
| **Azure Automation** | 1. Create an Automation Account ➞ *Runbook* ➞ **PowerShell 7.4**.<br>2. Paste & publish the script.<br>3. Enable *Managed Identity* and grant it **Cost Management Reader**.<br>4. Add a schedule (e.g. `0 2 1 * *` for 1 AM UTC monthly). |
| **GitHub Actions** | 1. Store a service‑principal secret (`AZURE_SP`).<br>2. Use `azure/login@v2` to authenticate:<br>   ```yaml
   - uses: azure/login@v2
     with:
       creds: ${{ secrets.AZURE_SP }}
   - run: pwsh ./azure-cost-report.ps1 …
   ``` |

---

## 8&nbsp; (Optional) archive or share the report

* **Email** – pipe the file through `Send-MailMessage`.  
* **Confluence / DevOps Wiki** – upload via their REST API.  
* **Blob Storage** – push to Azure Storage for audit:

```powershell
Set-AzStorageBlobContent -File $ReportPath `
    -Container billing `
    -Blob (Split-Path $ReportPath -Leaf)
```

---

## 9&nbsp; Keep everything current

```powershell
# Update the Az module
Update-Module Az -Force

# Update PowerShell itself
winget upgrade Microsoft.PowerShell
```

---

*You’re all set — regenerate detailed, tag‑aware cost reports any time, with no hidden charges.*  
