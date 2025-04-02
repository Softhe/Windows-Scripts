# Define the script parameter with a default fallback path
param (
    [string]$path = "%USERPROFILE%\Videos"
)

# Inform the user if the default path is being used
if (-not $PSBoundParameters.ContainsKey('path')) {
    Write-Host "No path specified, using default path: $path"
}

# Check if the path exists and is a directory
if (-not (Test-Path -Path $path -PathType Container)) {
    if (-not $PSBoundParameters.ContainsKey('path')) {
        Write-Error "The default path '$path' does not exist or is not a directory."
    } else {
        Write-Error "The specified path '$path' does not exist or is not a directory."
    }
    exit
}

# Set the log file path in the specified directory
$logFile = Join-Path -Path $path -ChildPath "DuplicateCleanupLog.txt"

# Log the start of the cleanup process
$now = Get-Date
Add-Content -Path $logFile -Value "Cleanup run at $now"

# Function to extract timestamp from file name
function Get-TimestampFromName {
    param ($fileName)
    $match = [regex]::Match($fileName, '\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}')
    if ($match.Success) {
        try {
            return [DateTime]::ParseExact($match.Value, 'yyyy-MM-dd HH-mm-ss', $null)
        } catch {
            return $null
        }
    }
    return $null
}

# Get all files in the directory, excluding the log file
$files = Get-ChildItem -Path $path -File | Where-Object { $_.Name -ne "DuplicateCleanupLog.txt" }

# Create a list of files with their parsed timestamps
$filesWithTimestamps = @()
foreach ($file in $files) {
    $timestamp = Get-TimestampFromName $file.Name
    if ($timestamp) {
        $filesWithTimestamps += [PSCustomObject]@{
            File = $file
            Timestamp = $timestamp
        }
    } else {
        Add-Content -Path $logFile -Value "Could not parse timestamp from '$($file.Name)', skipping"
    }
}

# Sort files by Timestamp and then by Name for consistency
$sortedFiles = $filesWithTimestamps | Sort-Object -Property Timestamp, @{Expression={$_.File.Name}}

# Initialize an array to store files marked for deletion
$toDelete = @()

# Check consecutive pairs of files for duplicates
for ($i = 0; $i -lt $sortedFiles.Count - 1; $i++) {
    $file1 = $sortedFiles[$i]
    $file2 = $sortedFiles[$i + 1]

    # Check if files are on the same date
    if ($file1.Timestamp.Date -eq $file2.Timestamp.Date) {
        $diff = ($file2.Timestamp - $file1.Timestamp).TotalSeconds
        Add-Content -Path $logFile -Value "Checked '$($file1.File.Name)' and '$($file2.File.Name)': same date, difference $diff seconds"
        
        # If time difference is 60 seconds or less, mark the older file for deletion
        if ($diff -le 60) {
            $toDelete += $file1.File
            Add-Content -Path $logFile -Value "Marking '$($file1.File.Name)' for deletion"
        } else {
            Add-Content -Path $logFile -Value "Time difference > 60 seconds, no action"
        }
    } else {
        Add-Content -Path $logFile -Value "Checked '$($file1.File.Name)' and '$($file2.File.Name)': different dates, no action"
    }
}

# Check if any files were marked for deletion
if ($toDelete.Count -eq 0) {
    Add-Content -Path $logFile -Value "No duplicates found"
    Write-Host "No duplicates found"
} else {
    # List the files to be deleted
    Write-Host "The following files will be deleted:"
    foreach ($file in $toDelete) {
        Write-Host "$($file.Name) - Timestamp: $(Get-TimestampFromName $file.Name)"
    }

    # Ask for user confirmation
    $response = Read-Host "Do you want to delete these files? (Y/N)"
    if ($response -eq 'Y' -or $response -eq 'y') {
        # Delete the files and log the actions
        foreach ($file in $toDelete) {
            Remove-Item -Path $file.FullName -Force
            Add-Content -Path $logFile -Value "Deleted '$($file.Name)'"
        }
    } else {
        Add-Content -Path $logFile -Value "User chose not to delete the files"
    }
}

# Log the completion of the cleanup
Add-Content -Path $logFile -Value "Cleanup completed"