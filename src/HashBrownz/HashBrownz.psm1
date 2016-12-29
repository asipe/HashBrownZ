Set-StrictMode -Version 'Latest'

$md5Algorithm = [Security.Cryptography.HashAlgorithm]::Create("MD5")
$bytesInAKB = 1024
$bytesInAMB = $bytesInAKB * 1024

Function Convert-HBZBytesToHexString {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [AllowEmptyCollection()] [byte[]]$bytes)

  [System.BitConverter]::ToString($bytes).Replace('-','') | Write-Output
}

Function Get-HBZS3FileMD5Hash {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path)

  $binaryHash = $null

  $strm = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try { 
    $binaryHash = $md5Algorithm.ComputeHash($strm)
  } finally {
    $strm.Close()
  }

  Convert-HBZBytesToHexString -Bytes $binaryHash | Write-Output
}

Function Get-HBZS3FileMultipartMD5Hash {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path,
        [Parameter(Mandatory=$true)] [int]$partSize)

  $parts = 0
  $buf = New-Object -TypeName byte[] -ArgumentList $partSize
  $binaryHash = @()

  $strm = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try {
    $streamLength = $strm.Length
    while (($bytesRead = $strm.Read($buf, 0, $buf.Length)) -ne 0) {
      if (($strm.Position -ne $streamLength) -and ($bytesRead -ne $buf.Length)) {
        throw 'Unable to read entire part buffer from stream'
      } else {
        $binaryHash += $md5Algorithm.ComputeHash($buf, 0, $bytesRead)
        $parts = $parts + 1
      }
    }
  } finally {
    $strm.Close()
  }

  $binaryHash = $md5Algorithm.ComputeHash($binaryHash)
  $hash = Convert-HBZBytesToHexString -Bytes $binaryHash
  '{0}-{1}' -f $hash,$parts | Write-Output
}

Function ConvertFrom-HBZS3FileMultipartETag {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$etag) 

  $parts = $etag -split '-'

  if ($parts.Length -ne 2) {
    throw 'Invalid Format'
  }

  $result = [pscustomobject]@{
    Hash = $parts[0]
    Parts = $parts[1]
  }

  $result | Write-Output
}

Function Get-HBZS3FileMultipartMD5HashPossiblePartSize {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$path,
        [Parameter(Mandatory=$true)] [string]$etag,
        [Parameter(Mandatory=$false)] [int]$partSizeIncrementBytes = $bytesInAMB)

  $parts = (ConvertFrom-HBZS3FileMultipartETag -etag $etag).Parts
  $fileLength = (Get-ChildItem -LiteralPath $path).Length
  $increment = 1

  while ($true) {
    $individualPartSize = $increment * $partSizeIncrementBytes
    $totalPartSize = $individualPartSize * $parts
    $fileLengthRemaining = $fileLength - $totalPartSize
    $overage = $fileLengthRemaining + $individualPartSize

    if (($fileLengthRemaining -le 0) -and ($overage -gt 0)) {
      $individualPartSize | Write-Output

      if ($parts -eq 1) {
        break;
      }
    }

    if ($overage -le 0) {
      break;
    }

    $increment += 1
  }
}

Function Test-HBZIsS3FileMultipartETag {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$etag) 

  $etag -match '-' | Write-Output
}

Function Get-HBZS3KeyForFile {
  [CmdletBinding()]
  Param([Parameter(Mandatory=$true)] [string]$localRoot,
        [Parameter(Mandatory=$true)] [string]$filePath,
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$prefix) 

  if ($localRoot[-1] -ne '\') {
    $localRoot += '\'
  }

  if (($prefix.Length -gt 0) -and ($prefix[-1] -ne '/')) {
    $prefix += '/'
  }

  $key = $filePath -ireplace ([System.Text.RegularExpressions.Regex]::Escape($localRoot)),''
  $key = $key.Replace('\', '/')
  '{0}{1}' -f $prefix,$key | Write-Output
}

Export-ModuleMember -Function *