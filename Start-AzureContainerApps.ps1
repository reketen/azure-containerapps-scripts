<#
.SYNOPSIS
    Starts all Azure Container Apps in a specified environment.
.DESCRIPTION
    This script retrieves all Container Apps in a specified Azure Container Apps Environment and starts them.
    It's designed to be used as part of a cost-saving automation to start Container Apps during business hours.
.PARAMETER ResourceGroupName
    The name of the resource group containing the Container Apps Environment.
.PARAMETER ContainerAppsEnvironmentName
    The name of the Container Apps Environment.
.EXAMPLE
    .\Start-AzureContainerApps.ps1 -ResourceGroupName "my-resource-group" -ContainerAppsEnvironmentName "my-container-apps-env"
.NOTES
    Requires the Az.App PowerShell module.
    Author: Oleksii Reketenets
    Date: May 9, 2025
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$ContainerAppsEnvironmentName
)

# Function to check and install required modules
function Ensure-ModuleInstalled {
    param(
        [string]$ModuleName
    )
    
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Output "The $ModuleName module is not installed. Installing it now..."
        try {
            # Install the module without confirmation prompts
            Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Output "$ModuleName module installed successfully."
            return $true
        }
        catch {
            Write-Error "Failed to install $ModuleName module. Error: $_"
            return $false
        }
    }
    else {
        Write-Output "$ModuleName module is already installed."
        return $true
    }
}

# Ensure the Az.App module is installed
if (-not (Ensure-ModuleInstalled -ModuleName "Az.App")) {
    exit 1
}

# Check if we are connected to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not connected to Azure. Please run Connect-AzAccount first."
        exit 1
    }
    Write-Output "Connected to Azure subscription: $($context.Subscription.Name)"
} 
catch {
    Write-Error "Error checking Azure connection: $_"
    exit 1
}

# Start logging
$logFile = "ContainerApps_Start_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting Container Apps startup process" | Out-File -FilePath $logFile -Append

# Retrieve all Container Apps in the specified environment
try {
    Write-Output "Retrieving Container Apps in environment '$ContainerAppsEnvironmentName' in resource group '$ResourceGroupName'..."
    
    $containerApps = Get-AzContainerApp -ResourceGroupName $ResourceGroupName | 
                     Where-Object { $_.ManagedEnvironmentId -like "*/$ContainerAppsEnvironmentName" }
    
    if (-not $containerApps -or $containerApps.Count -eq 0) {
        $message = "No Container Apps found in environment '$ContainerAppsEnvironmentName' in resource group '$ResourceGroupName'."
        Write-Warning $message
        $message | Out-File -FilePath $logFile -Append
        exit 0
    }
    
    Write-Output "Found $($containerApps.Count) Container Apps to start."
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Found $($containerApps.Count) Container Apps to start" | Out-File -FilePath $logFile -Append
}
catch {
    $errorMessage = "Error retrieving Container Apps: $_"
    Write-Error $errorMessage
    $errorMessage | Out-File -FilePath $logFile -Append
    exit 1
}

# Start each Container App
$successCount = 0
$failCount = 0

foreach ($app in $containerApps) {
    try {      
        Write-Output "Starting Container App: $($app.Name)..."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Attempting to start Container App: $($app.Name)" | Out-File -FilePath $logFile -Append
        
        # Start the Container App
        Start-AzContainerApp -Name $app.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        Write-Output "Successfully started Container App: $($app.Name)"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Successfully started Container App: $($app.Name)" | Out-File -FilePath $logFile -Append
        $successCount++
    }
    catch {
        $errorMessage = "Failed to start Container App $($app.Name): $_"
        Write-Error $errorMessage
        $errorMessage | Out-File -FilePath $logFile -Append
        $failCount++
    }
}

# Output summary
$summary = @"
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Container Apps startup process completed
Total Container Apps: $($containerApps.Count)
Successfully started: $successCount
Failed to start: $failCount
"@

Write-Output $summary
$summary | Out-File -FilePath $logFile -Append

if ($failCount -gt 0) {
    Write-Warning "Some Container Apps failed to start. Check the log file: $logFile"
    exit 1
}
else {
    Write-Output "All Container Apps successfully started. Details in log file: $logFile"
    exit 0
}