<#
.SYNOPSIS
    Stops all Azure Container Apps in a specified environment.
.DESCRIPTION
    This script retrieves all Container Apps in a specified Azure Container Apps Environment and stops them.
    It's designed to be used as part of a cost-saving automation to shut down Container Apps outside of business hours.
.PARAMETER ResourceGroupName
    The name of the resource group containing the Container Apps.
.PARAMETER ContainerAppsEnvironmentName
    The name of the Container Apps Environment.
.PARAMETER CAEResourceGroupName
    The name of the resource group containing the Container Apps Environment.
.EXAMPLE
    .\Stop-AzureContainerApps.ps1 -ResourceGroupName "my-resource-group" -ContainerAppsEnvironmentName "my-container-apps-env" -CAEResourceGroupName "my-container-apps-env-rg"
.NOTES
    Requires the Az.App PowerShell module.
    Author: Oleksii Reketenets
    Date: May 16, 2025
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$ContainerAppsEnvironmentName,

     [Parameter(Mandatory = $true)]
    [string]$CAEResourceGroupName
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
$logFile = "ContainerApps_Stop_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting Container Apps shutdown process" | Out-File -FilePath $logFile -Append

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
    
    Write-Output "Found $($containerApps.Count) Container Apps to stop."
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Found $($containerApps.Count) Container Apps to stop" | Out-File -FilePath $logFile -Append
}
catch {
    $errorMessage = "Error retrieving Container Apps: $_"
    Write-Error $errorMessage
    $errorMessage | Out-File -FilePath $logFile -Append
    exit 1
}

# Stop each Container App
$successCount = 0
$failCount = 0

foreach ($app in $containerApps) {
    try {
        Write-Output "Stopping Container App: $($app.Name)..."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Attempting to stop Container App: $($app.Name)" | Out-File -FilePath $logFile -Append
        
        # Stop the Container App
        Stop-AzContainerApp -Name $app.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        Write-Output "Successfully stopped Container App: $($app.Name)"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Successfully stopped Container App: $($app.Name)" | Out-File -FilePath $logFile -Append
        $successCount++
    }
    catch {
        $errorMessage = "Failed to stop Container App $($app.Name): $_"
        Write-Error $errorMessage
        $errorMessage | Out-File -FilePath $logFile -Append
        $failCount++
    }
}

# Output summary
$summary = @"
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Container Apps shutdown process completed
Total Container Apps: $($containerApps.Count)
Successfully stopped: $successCount
Failed to stop: $failCount
"@

Write-Output $summary
$summary | Out-File -FilePath $logFile -Append

if ($failCount -gt 0) {
    Write-Warning "Some Container Apps failed to stop. Check the log file: $logFile"
    exit 1
}
else {
    Write-Output "All Container Apps successfully stopped. Details in log file: $logFile"
    exit 0
}

# Check the Container Apps Environment status and fix if needed
try {
    Write-Output "Checking status of Container Apps Environment '$ContainerAppsEnvironmentName' in resource group '$CAEResourceGroupName'..."
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Checking status of Container Apps Environment '$ContainerAppsEnvironmentName'" | Out-File -FilePath $logFile -Append
    
    $environment = Get-AzContainerAppManagedEnv -ResourceGroupName $CAEResourceGroupName -Name $ContainerAppsEnvironmentName -ErrorAction Stop
    
    Write-Output "Container Apps Environment status: $($environment.ProvisioningState)"
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Container Apps Environment status: $($environment.ProvisioningState)" | Out-File -FilePath $logFile -Append
    
    # If the environment is in FAILED state, fix it by adding a tag
    if ($environment.ProvisioningState -eq "Failed") {
        $currentDate = Get-Date -Format "yyyyMMdd"
        $tagName = "Shutdown$currentDate"
        $tagValue = Get-Date -Format "yyyy-MM-dd"
        
        Write-Output "Container Apps Environment is in FAILED state. Applying fix by adding tag: $tagName = $tagValue"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Container Apps Environment is in FAILED state. Applying fix by adding tag: $tagName = $tagValue" | Out-File -FilePath $logFile -Append
        
        # Create tag hashtable
        $tagHash = @{$tagName = $tagValue}
        
        # Preserve existing tags if any
        if ($environment.Tag) {
            foreach ($key in $environment.Tag.Keys) {
                if ($key -ne $tagName) {  # Don't duplicate our new tag
                    $tagHash[$key] = $environment.Tag[$key]
                }
            }
        }
        
        # Apply the tag to fix the environment
        Update-AzContainerAppManagedEnv -ResourceGroupName $CAEResourceGroupName -Name $ContainerAppsEnvironmentName -Tag $tagHash -ErrorAction Stop
        
        Write-Output "Fix applied successfully."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fix applied successfully." | Out-File -FilePath $logFile -Append
        
        # Verify the environment status after fix
        $environment = Get-AzContainerAppManagedEnv -ResourceGroupName $CAEResourceGroupName -Name $ContainerAppsEnvironmentName -ErrorAction Stop
        Write-Output "Container Apps Environment status after fix: $($environment.ProvisioningState)"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Container Apps Environment status after fix: $($environment.ProvisioningState)" | Out-File -FilePath $logFile -Append
    }
}
catch {
    $errorMessage = "Error checking or fixing Container Apps Environment: $_"
    Write-Error $errorMessage
    $errorMessage | Out-File -FilePath $logFile -Append
}
