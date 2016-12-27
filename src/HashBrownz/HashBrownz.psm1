Set-StrictMode -Version 'Latest'

$md5Algorithm = [Security.Cryptography.HashAlgorithm]::Create("MD5")

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
    $pos = 0
    $streamLength = $strm.Length
    while (($bytesRead = $strm.Read($buf, $pos, $buf.Length - $pos)) -ne 0) {
      if (($strm.Position -ne $streamLength) -and ($bytesRead -ne $buf.Length)) {
        Write-Host 'hi'
        $pos = $bytesRead 
      } else {
        $binaryHash += $md5Algorithm.ComputeHash($buf, 0, $bytesRead + $pos)
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

Export-ModuleMember -Function *