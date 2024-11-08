param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [Parameter(Mandatory = $false)]
    [int]$MinSize = 10485760,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

function Write-DirectorySizeInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [int]$MinSize = 10485760
    )
   
    # Verify that the path exists
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "The path '$Path' does not exist."
        return @{ Size = 0; Json = $null }
    }
    try {
        $CurrentItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Write-Error "Failed to get item at path '$Path': $($_.Exception.Message)"
        return @{ Size = 0; Json = $null }
    }

    # Skip processing if the item is a reparse point (e.g., symlink, junction)
    if ($CurrentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Verbose "Skipping reparse point: $($CurrentItem.FullName)"
        return @{ Size = 0; Json = $null }
    }

    $ItemType = if ($CurrentItem.PSIsContainer) { 'Directory' } else { 'File' }
    $Properties = @{
        Name      = $CurrentItem.Name
        FullName  = $CurrentItem.FullName
        ItemType  = $ItemType
        Errors    = @()
        Size      = 0
    }
    $Children = @()
    if ($ItemType -eq 'Directory') {
        # Process child items
        try {
            $ChildItems = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
            foreach ($ChildItem in $ChildItems) {
                $ChildResult = Write-DirectorySizeInfo -Path $ChildItem.FullName -MinSize $MinSize
                $Properties.Size += $ChildResult.Size
                if ($ChildResult.Json) {
                    $Children += $ChildResult.Json
                }
            }
        } catch {
            $Properties['Errors'] += $_.Exception.Message
        }
       
        # Include directory if it meets MinSize or has qualifying children
        if ($Properties.Size -ge $MinSize -or $Children.Count -gt 0) {
            if ($Children.Count -gt 0) {
                $Properties['Children'] = $Children
            }
            return @{
                Size = $Properties.Size
                Json = $Properties
            }
        } else {
            return @{ Size = $Properties.Size; Json = $null }
        }
    } else {
        # File: get size
        try {
            $Properties.Size = $CurrentItem.Length
        } catch {
            $Properties['Errors'] += $_.Exception.Message
        }
        # Include file if it meets MinSize
        if ($Properties.Size -ge $MinSize) {
            return @{
                Size = $Properties.Size
                Json = $Properties
            }
        } else {
            return @{ Size = $Properties.Size; Json = $null }
        }
    }
}

$Result = Write-DirectorySizeInfo -Path $RootPath -MinSize $MinSize
if ($Result.Json) {
    $JsonOutput = ConvertTo-Json $Result.Json -Depth 100
    if ($OutputPath) {
        [System.IO.File]::WriteAllText($OutputPath, $JsonOutput)
    } else {
        Write-Host $JsonOutput
    }
} else {
    Write-Host "No items meet the minimum size criteria."
}