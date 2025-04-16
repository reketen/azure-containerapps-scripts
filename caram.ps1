# Set your variables
$ResourceGroup = "n8n"
$ContainerAppsEnvironment = "cae-n8n-1"

# Initialize total memory in GB
$TotalMemoryGB = 0

# List all container apps in the environment
Write-Host "Fetching all container apps in $ContainerAppsEnvironment..."
$ContainerApps = (az containerapp list `
  --resource-group $ResourceGroup `
  --environment $ContainerAppsEnvironment `
  --query '[].name' -o tsv) | Out-String -Stream

Write-Host "Calculating RAM reservation for all container apps..."
Write-Host "---------------------------------------------"

# Loop through each container app
foreach ($App in $ContainerApps) {
    if (-not [string]::IsNullOrWhiteSpace($App)) {
        Write-Host "Container App: $App"
        
        # Get container app details
        $AppDetailsJson = az containerapp show `
            --name $App `
            --resource-group $ResourceGroup
        
        $AppDetails = $AppDetailsJson | ConvertFrom-Json
        
        # Get scale settings to account for minimum replicas
        $MinReplicas = 1  # Default value
        if ($AppDetails.properties.template.scale.PSObject.Properties.Name -contains "minReplicas") {
            $MinReplicas = $AppDetails.properties.template.scale.minReplicas
        }
        Write-Host "  Minimum replicas: $MinReplicas"
        
        # Initialize app memory
        $AppMemoryGB = 0
        
        # Process each container
        $ContainerCount = 0
        foreach ($Container in $AppDetails.properties.template.containers) {
            $ContainerCount++
            
            # Extract memory reservation for this container
            $ContainerMemoryRaw = $Container.resources.memory
            
            # Handle Gi notation (e.g., "1Gi", "2Gi")
            if ($ContainerMemoryRaw -match "(\d+)Gi") {
                $ContainerMemory = [double]$Matches[1]
                Write-Host "  Container $ContainerCount ($($Container.name)): ${ContainerMemory}GB (from ${ContainerMemoryRaw})"
            } else {
                # Try to directly convert if it's a plain number
                try {
                    $ContainerMemory = [double]$ContainerMemoryRaw
                    Write-Host "  Container $ContainerCount ($($Container.name)): ${ContainerMemory}GB"
                } catch {
                    Write-Host "  Container $ContainerCount ($($Container.name)): Could not parse memory value: $ContainerMemoryRaw" -ForegroundColor Red
                    $ContainerMemory = 0
                }
            }
            
            # Add to app memory
            $AppMemoryGB += $ContainerMemory
        }
        
        # Calculate total memory for this app (all containers × min replicas)
        $TotalAppMemory = $AppMemoryGB * $MinReplicas
        
        Write-Host "  Total app memory: ${TotalAppMemory}GB (${AppMemoryGB}GB × $MinReplicas replicas)"
        Write-Host "---------------------------------------------"
        
        # Add to total
        $TotalMemoryGB += $TotalAppMemory
    }
}

Write-Host "Total RAM reservation across all apps: ${TotalMemoryGB}GB"