# Intersight Configuration (Replace with your actual values)
$ApiParams = @{
    BasePath = "https://Intersight.com"
    ApiKeyId = "Paste_your_API_key_here"
    ApiKeyFilePath = $pwd.Path + "\SecretKey.txt"
    HttpSigningHeader = @("(request-target)", "Host", "Date", "Digest")
}

# Initiate Intersight connection
try {
    Set-IntersightConfiguration @ApiParams
} catch {
    Write-Error "Failed to connect to Intersight: $($_.Exception.Message)"
    exit  # Stop script execution if connection fails
}

# Define the output CSV file
$outputCsv = "ConsolidatedServerInventory.csv"

# Initialize an array to store all the data
$inventoryData = @()

# Retrieve the summary of physical servers
try {
    $servers = Get-IntersightComputePhysicalSummary -Top 1000
    if (-not $servers.Results) {
        Write-Warning "No servers found in Intersight."
        exit
    }
} catch {
    Write-Error "Failed to retrieve server data: $($_.Exception.Message)"
    exit # Stop if cannot get server data
}

# Function to safely access nested properties
function Get-NestedProperty {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Object,
        [Parameter(Mandatory = $true)]
        [string]$PropertyPath
    )
    $value = $Object
    foreach ($property in $PropertyPath.Split('.')) {
        if ($value -is [PSCustomObject] -and $value.PSObject.Properties[$property]) {
            $value = $value."$property"
        } else {
            return $null # Return null if any property in the path is not found
        }
    }
    return $value
}

# Function to find Model and Serial
function Find-ModelSerial {
    param([PSObject]$Object)
    $localModel = $null
    $localSerial = $null
    $localPid = $null

    # Check direct properties
    if ($Object.Model) { $localModel = $Object.Model }
    if ($Object.Serial) { $localSerial = $Object.Serial }
    if ($Object.Pid)   { $localPid = $Object.Pid   }

    # Check AdditionalProperties
    if ($Object.AdditionalProperties) {
        if ($Object.AdditionalProperties.Model) { $localModel = $Object.AdditionalProperties.Model }
        if ($Object.AdditionalProperties.Serial) { $localSerial = $Object.AdditionalProperties.Serial }
        if ($Object.AdditionalProperties.Pid)   { $localPid = $Object.AdditionalProperties.Pid   }
        # Check for nested properties within AdditionalProperties
        if ($Object.AdditionalProperties.Properties)
        {
           if ($Object.AdditionalProperties.Properties.Model) {$localModel = $Object.AdditionalProperties.Properties.Model}
           if ($Object.AdditionalProperties.Properties.Serial) {$localSerial = $Object.AdditionalProperties.Properties.Serial}
           if ($Object.AdditionalProperties.Properties.Pid)   {$localPid = $Object.AdditionalProperties.Properties.Pid}
        }
    }
     if ($Object.Properties)
    {
       if ($Object.Properties.Model) {$localModel = $Object.Properties.Model}
       if ($Object.Properties.Serial) {$localSerial = $Object.Properties.Serial}
       if ($Object.Properties.Pid)   {$localPid = $Object.Properties.Pid}
    }

    return @{ Model = $localModel; Serial = $localSerial; Pid = $localPid }
}


# Process each server
foreach ($server in $servers.Results) {
    # Prepare a hashtable for the current server's row
    $serverRow = [ordered]@{ # Use Ordered Dictionary to maintain column order.
        "Server Name"     = $server.Name
        "Server Model"    = $server.Model
        "Server Serial"   = $server.Serial
        "Server Firmware" = $server.Firmware
    }

    # Build the filter for related components. Include cond.Alarm in the initial query.
    $filter = "(Ancestors/any(t:t/Moid eq '$($server.Moid)')) or (ObjectType eq 'cond.Alarm' and AncestorMoId eq '$($server.Moid)')"
    try {
        $results = Get-IntersightSearchSearchItem -Filter $filter -Top 1000
    } catch {
        Write-Error "Failed to retrieve component data for server $($server.Name): $($_.Exception.Message)"
        # Consider whether to continue to the next server or stop.  Here, continue.
        continue
    }

    # Initialize component lists (now hashtables for counting)
    $processors = @{}
    $memoryModules = @{}
    $storageDevices = @{}
    $alarms = @() # Array to hold alarm information

    # Process each result
    foreach ($result in $results.Results) {
        if ($result.ObjectType -eq 'ProcessorUnit') {
            $modelSerial = Find-ModelSerial -Object $result
            $key = "PID: $($modelSerial.Pid), Model: $($modelSerial.Model)"  # Use PID as key
            if ($processors.ContainsKey($key)) {
                $processors[$key]++
            } else {
                $processors[$key] = 1
            }
        } elseif ($result.ObjectType -match 'MemoryUnit') {
            $modelSerial = Find-ModelSerial -Object $result
            $key = "PID: $($modelSerial.Pid), Model: $($modelSerial.Model)"
             if ($memoryModules.ContainsKey($key)) {
                $memoryModules[$key]++
            } else {
                $memoryModules[$key] = 1
            }
        } elseif ($result.ObjectType -match 'StorageController|StorageDisk|StorageUnit') {
            $modelSerial = Find-ModelSerial -Object $result
            $key = "PID: $($modelSerial.Pid), Model: $($modelSerial.Model)"
            if ($storageDevices.ContainsKey($key)) {
                $storageDevices[$key]++
            } else {
                $storageDevices[$key] = 1
            }
        } elseif ($result.ObjectType -eq 'cond.Alarm') {
            # Extract alarm properties.  Use Get-NestedProperty for safety.
            $alarmSeverity = Get-NestedProperty -Object $result -PropertyPath "Status"
            $alarmDescription = Get-NestedProperty -Object $result -PropertyPath "Description"
            $alarms += "$($alarmSeverity): $($alarmDescription)"
        }
    }

    # Add components to the server row, include counts
    $processorString = ($processors.GetEnumerator() | ForEach-Object { "$($_.Key) (Count: $($_.Value))" }) -join " | "
    $serverRow."Processors" = $processorString

    $memoryString = ($memoryModules.GetEnumerator() | ForEach-Object { "$($_.Key) (Count: $($_.Value))" }) -join " | "
    $serverRow."Memory Modules" = $memoryString

    $storageString = ($storageDevices.GetEnumerator() | ForEach-Object { "$($_.Key) (Count: $($_.Value))" }) -join " | "
    $serverRow."Storage Devices" = $storageString
    $serverRow."Alarms"         = ($alarms -join " | ") # Add Alarms to the output

    # Add the server row to the inventory data array
    $inventoryData += $serverRow
}

# Export the consolidated inventory data to a CSV file
try {
    $inventoryData | Export-Csv -Path $outputCsv -NoTypeInformation -Force
    Write-Host "Consolidated server inventory has been exported to $outputCsv successfully."
} catch {
    Write-Error "Failed to export data to CSV: $($_.Exception.Message)"
    exit
}

