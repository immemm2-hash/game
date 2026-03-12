param(
  [int]$Port = 5500,
  [string]$Root = "c:\work\workspace"
)

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Output "Serving $Root at http://localhost:$Port/"

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

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $reader = [System.IO.StreamReader]::new($stream)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }

    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line -or $line -eq '') { break }
    }

    $parts = $requestLine.Split(' ')
    $method = $parts[0]
    $urlPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }

    if ($method -ne 'GET') {
      $body = [Text.Encoding]::UTF8.GetBytes('Method Not Allowed')
      $headers = "HTTP/1.1 405 Method Not Allowed`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
      $h = [Text.Encoding]::ASCII.GetBytes($headers)
      $stream.Write($h,0,$h.Length); $stream.Write($body,0,$body.Length)
      $client.Close(); continue
    }

    $cleanPath = $urlPath.Split('?')[0].TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($cleanPath)) { $cleanPath = 'index.html' }
    $cleanPath = [Uri]::UnescapeDataString($cleanPath).Replace('/','\')
    $fullPath = Join-Path $Root $cleanPath

    if ((Test-Path $fullPath) -and -not (Get-Item $fullPath).PSIsContainer) {
      $body = [IO.File]::ReadAllBytes($fullPath)
      $ctype = Get-ContentType $fullPath
      $headers = "HTTP/1.1 200 OK`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
      $h = [Text.Encoding]::ASCII.GetBytes($headers)
      $stream.Write($h,0,$h.Length); $stream.Write($body,0,$body.Length)
    } else {
      $body = [Text.Encoding]::UTF8.GetBytes('404 Not Found')
      $headers = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
      $h = [Text.Encoding]::ASCII.GetBytes($headers)
      $stream.Write($h,0,$h.Length); $stream.Write($body,0,$body.Length)
    }

    $stream.Flush()
  } catch {
  } finally {
    $client.Close()
  }
}
