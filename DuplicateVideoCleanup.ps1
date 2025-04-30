<#
How to Use the Script

    Save the Script: Save it as DuplicateVideoCleanup.ps1.
    Run the Script: Open PowerShell cd to script folder and execute it with parameters.

cd "C:\Users\Administrator\Downloads"
.\DuplicateVideoCleanup.ps1 -Directory "C:\Users\Administrator\Videos" -Threshold 60 -Keep "Oldest"

    -Directory: Path to the folder containing video files (required).
    -Threshold: Maximum time difference in seconds to consider files duplicates (default: 60).
    -Keep: "Oldest" or "Newest" to decide which file to retain (default: "Oldest").

What It Does:

    Scans the specified directory for .mkv and .mp4 files.
    Extracts timestamps from filenames (e.g., "2025-04-29 21-57-03") or uses CreationTime if the filename lacks a timestamp.
    Groups files with timestamps within the threshold.
    Lists each group, showing all files, the one to keep, and those to delete.
    Prompts for confirmation before deleting.
    Logs everything to DuplicateCleanupLog.txt in the specified directory.

#>


param(
    [Parameter(Mandatory=$true)]
    [string]$Directory,
    [int]$Threshold = 60,
    [ValidateSet("Oldest", "Newest")]
    [string]$Keep = "Oldest"
)

# Start logging to DuplicateCleanupLog.txt in the specified directory
Start-Transcript -Path "$Directory\DuplicateCleanupLog.txt" -Append

# Display script parameters
Write-Host "Cleaning duplicates in directory: $Directory"
Write-Host "Threshold: $Threshold seconds"
Write-Host "Keep: $Keep"
Write-Host ""

# Check if directory exists
if (-not (Test-Path $Directory)) {
    Write-Error "Directory '$Directory' does not exist."
    Stop-Transcript
    exit
}

# Get all .mkv and .mp4 files in the directory
$files = Get-ChildItem -Path $Directory -File | Where-Object { $_.Extension -eq ".mkv" -or $_.Extension -eq ".mp4" }

if ($files.Count -eq 0) {
    Write-Host "No .mkv or .mp4 files found in '$Directory'."
    Stop-Transcript
    exit
}

# Extract timestamps from filenames or use CreationTime as fallback
$timedFiles = @()
foreach ($file in $files) {
    $match = [regex]::Match($file.Name, "\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}")
    if ($match.Success) {
        $timestampStr = $match.Value
        try {
            $timestamp = [DateTime]::ParseExact($timestampStr, "yyyy-MM-dd HH-mm-ss", $null)
        } catch {
            Write-Warning "Failed to parse timestamp from '$($file.Name)', using CreationTime."
            $timestamp = $file.CreationTime
        }
    } else {
        $timestamp = $file.CreationTime
    }
    $timedFiles += [PSCustomObject]@{ File = $file; Timestamp = $timestamp }
}

# Sort files by timestamp
$sortedFiles = $timedFiles | Sort-Object Timestamp

# Group files where consecutive timestamps are within the threshold
$groups = @()
$currentGroup = @()
$previousTime = $null
foreach ($tf in $sortedFiles) {
    if ($previousTime -eq $null -or ($tf.Timestamp - $previousTime).TotalSeconds -le $Threshold) {
        $currentGroup += $tf
    } else {
        if ($currentGroup.Count -gt 1) {
            $groups += ,$currentGroup
        }
        $currentGroup = @($tf)
    }
    $previousTime = $tf.Timestamp
}
if ($currentGroup.Count -gt 1) {
    $groups += ,$currentGroup
}

# Process duplicate groups
if ($groups.Count -eq 0) {
    Write-Host "No duplicates found within $Threshold seconds."
} else {
    Write-Host "Found duplicates:"
    Write-Host ""
    $toDelete = @()
    
    foreach ($group in $groups) {
        # Determine which file to keep
        if ($Keep -eq "Oldest") {
            $keepFile = $group[0]
            $deleteFiles = $group[1..($group.Count-1)]
        } else {
            $keepFile = $group[-1]
            $deleteFiles = $group[0..($group.Count-2)]
        }
        
        # Display group details
        Write-Host "Group:"
        foreach ($tf in $group) {
           Write-Host "  $($tf.File.Name) - $($tf.Timestamp)"
        }
        Write-Host "Keep: " -NoNewline
        Write-Host "$(keepFile.File.Name) - $(tf.Timestamp)" -ForegroundColor Green
        Write-Host "Delete:"
        foreach ($tf in $deleteFiles) {
            Write-Host "  $($tf.File.Name)" -ForegroundColor Red
            $toDelete += $tf.File
        }
        Write-Host ""
    }
    
    # Ask for confirmation
    $confirmation = Read-Host "Proceed with deletion? (Y/N)"
    if ($confirmation -eq "Y") {
        foreach ($file in $toDelete) {
            try {
                Remove-Item $file.FullName -Force
                Write-Host "Deleted: $($file.Name)"
            } catch {
                Write-Error "Failed to delete '$($file.Name)': $_"
            }
        }
        Write-Host "Deletion completed."
    } else {
        Write-Host "Deletion cancelled."
    }
}

# Stop logging
Stop-Transcript