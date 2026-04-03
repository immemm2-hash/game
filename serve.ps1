param(
  [int]$Port = 5500,
  [string]$Root = "c:\work\workspace"
)

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Output "Serving $Root at http://localhost:$Port/"

$rankingFile = Join-Path $Root 'ranking.json'
if (-not (Test-Path $rankingFile)) {
  '[]' | Set-Content -Path $rankingFile -Encoding UTF8 -NoNewline
}

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.js' { 'application/javascript; charset=utf-8' }
    '.css' { 'text/css; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.svg' { 'image/svg+xml' }
    default { 'application/octet-stream' }
  }
}

function Send-BytesResponse($stream, [int]$statusCode, [string]$statusText, [string]$contentType, [byte[]]$body) {
  $headers = "HTTP/1.1 $statusCode $statusText`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nConnection: close`r`nAccess-Control-Allow-Origin: *`r`n`r`n"
  $h = [Text.Encoding]::ASCII.GetBytes($headers)
  $stream.Write($h, 0, $h.Length)
  if ($body.Length -gt 0) {
    $stream.Write($body, 0, $body.Length)
  }
}

function Send-JsonResponse($stream, [int]$statusCode, [string]$statusText, $obj) {
  $json = $obj | ConvertTo-Json -Depth 6 -Compress
  $body = [Text.Encoding]::UTF8.GetBytes($json)
  Send-BytesResponse $stream $statusCode $statusText 'application/json; charset=utf-8' $body
}

function Normalize-Ranking($items) {
  $arr = @()
  foreach ($it in @($items)) {
    if (-not $it) { continue }
    if (-not ($it.PSObject.Properties.Name -contains 'name')) { continue }
    if (-not ($it.PSObject.Properties.Name -contains 'score')) { continue }

    $name = [string]$it.name
    $name = $name.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = '플레이어' }
    if ($name.Length -gt 12) { $name = $name.Substring(0, 12) }

    try {
      $score = [int][Math]::Floor([double]$it.score)
    } catch {
      continue
    }
    if ($score -lt 0) { $score = 0 }

    $arr += [PSCustomObject]@{ name = $name; score = $score }
  }

  return @($arr | Sort-Object -Property score -Descending | Select-Object -First 10)
}

function Read-Ranking([string]$filePath) {
  try {
    $raw = Get-Content -Path $filePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return ,(Normalize-Ranking @($parsed))
  } catch {
    return @()
  }
}

function Write-Ranking([string]$filePath, $items) {
  $normalized = Normalize-Ranking $items
  ConvertTo-Json -InputObject @($normalized) -Depth 4 | Set-Content -Path $filePath -Encoding UTF8 -NoNewline
  return $normalized
}

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $reader = [System.IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }

    $parts = $requestLine.Split(' ')
    $method = $parts[0]
    $urlPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }

    $headers = @{}
    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line -or $line -eq '') { break }
      $idx = $line.IndexOf(':')
      if ($idx -gt 0) {
        $k = $line.Substring(0, $idx).Trim().ToLowerInvariant()
        $v = $line.Substring($idx + 1).Trim()
        $headers[$k] = $v
      }
    }

    if ($method -eq 'OPTIONS') {
      $body = [byte[]]::new(0)
      $resp = "HTTP/1.1 204 No Content`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
      $h = [Text.Encoding]::ASCII.GetBytes($resp)
      $stream.Write($h, 0, $h.Length)
      $stream.Flush()
      continue
    }

    $cleanPath = $urlPath.Split('?')[0].TrimStart('/')

    if (($method -eq 'GET') -and ($cleanPath -eq 'api/ranking')) {
      $ranking = Read-Ranking $rankingFile
      Send-JsonResponse $stream 200 'OK' @{ ranking = @($ranking) }
      $stream.Flush()
      continue
    }

    if (($method -eq 'POST') -and ($cleanPath -eq 'api/ranking')) {
      $contentLength = 0
      if ($headers.ContainsKey('content-length')) {
        [void][int]::TryParse($headers['content-length'], [ref]$contentLength)
      }

      $bodyText = ''
      if ($contentLength -gt 0) {
        $bodyBytes = New-Object byte[] $contentLength
        $readTotal = 0
        while ($readTotal -lt $contentLength) {
          $read = $stream.Read($bodyBytes, $readTotal, $contentLength - $readTotal)
          if ($read -le 0) { break }
          $readTotal += $read
        }
        $bodyText = [Text.Encoding]::UTF8.GetString($bodyBytes, 0, $readTotal)
      }

      try {
        $payload = $bodyText | ConvertFrom-Json
      } catch {
        Send-JsonResponse $stream 400 'Bad Request' @{ error = 'Invalid JSON body.' }
        $stream.Flush()
        continue
      }

      $name = ''
      if ($payload -and ($payload.PSObject.Properties.Name -contains 'name')) {
        $name = [string]$payload.name
      }
      $name = $name.Trim()
      if ([string]::IsNullOrWhiteSpace($name)) { $name = '플레이어' }
      if ($name.Length -gt 12) { $name = $name.Substring(0, 12) }

      try {
        $score = [int][Math]::Floor([double]$payload.score)
      } catch {
        Send-JsonResponse $stream 400 'Bad Request' @{ error = 'Invalid score.' }
        $stream.Flush()
        continue
      }

      if ($score -le 0) {
        Send-JsonResponse $stream 400 'Bad Request' @{ error = 'Score must be greater than 0.' }
        $stream.Flush()
        continue
      }

      $ranking = Read-Ranking $rankingFile
      $accepted = $false
      if (($ranking.Count -lt 10) -or ($score -gt $ranking[-1].score)) {
        $ranking += [PSCustomObject]@{ name = $name; score = $score }
        $ranking = Write-Ranking $rankingFile $ranking
        $accepted = $true
      }

      Send-JsonResponse $stream 200 'OK' @{ accepted = $accepted; ranking = @($ranking) }
      $stream.Flush()
      continue
    }

    if (($method -ne 'GET')) {
      $body = [Text.Encoding]::UTF8.GetBytes('Method Not Allowed')
      Send-BytesResponse $stream 405 'Method Not Allowed' 'text/plain; charset=utf-8' $body
      $stream.Flush()
      continue
    }

    if ([string]::IsNullOrWhiteSpace($cleanPath)) { $cleanPath = 'index.html' }
    $safeRelPath = [Uri]::UnescapeDataString($cleanPath).Replace('/', '\')
    if ($safeRelPath.Contains('..')) {
      $body = [Text.Encoding]::UTF8.GetBytes('403 Forbidden')
      Send-BytesResponse $stream 403 'Forbidden' 'text/plain; charset=utf-8' $body
      $stream.Flush()
      continue
    }

    $fullPath = Join-Path $Root $safeRelPath
    if ((Test-Path $fullPath) -and -not (Get-Item $fullPath).PSIsContainer) {
      $body = [IO.File]::ReadAllBytes($fullPath)
      $ctype = Get-ContentType $fullPath
      Send-BytesResponse $stream 200 'OK' $ctype $body
    } else {
      $body = [Text.Encoding]::UTF8.GetBytes('404 Not Found')
      Send-BytesResponse $stream 404 'Not Found' 'text/plain; charset=utf-8' $body
    }

    $stream.Flush()
  } catch {
  } finally {
    $client.Close()
  }
}
