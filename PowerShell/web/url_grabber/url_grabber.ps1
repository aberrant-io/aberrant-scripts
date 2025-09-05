<#
.SYNOPSIS
    Retrieves content from a specified URL and saves it to a file.

.DESCRIPTION
    This script takes a URL as a parameter, downloads the content from that URL, and saves it to a file in the Output directory. If a file with the same name already exists, it will be overwritten.

.PARAMETER url
    The URL from which to download content. This is a mandatory parameter.

.EXAMPLE
    .\url_grabber.ps1 -url "http://example.com"

    This command will download the content from "http://example.com" and save it to a file in the Output directory.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$url
)

try {
    # Download the content from the URL
    $content = Invoke-WebRequest -Uri $url -UseBasicParsing | Select-Object -ExpandProperty Content

    # Extract the filename from the URL (or use a default)
    $uri = New-Object System.Uri($url)
    $tmpfilename = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    if ([string]::IsNullOrEmpty($tmpfilename)) {
        $tmpfilename = "downloaded_content.txt" # Default filename
    }

    $FilePath = ".\Output\$tmpfilename"
    # Check if the file exists
    if (Test-Path -Path $FilePath) {
        # Delete the existing file
        Remove-Item -Path $FilePath -Force 
    }

    # Save the content to a file
    $content | Out-File -FilePath $FilePath

    # build output manifest
    $OutputManifest = @{
        Files = @($tmpfilename)
        Links = @($url)
    }
    $OutputParameters = @{
        Url = $url
    }
    # Create the output wrapper object, wrapping the parameters and the Manifest
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest = $OutputManifest
    }
    # write the output as json
    Write-Output $ScriptOutput | ConvertTo-Json

} catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
}