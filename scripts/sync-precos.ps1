$ErrorActionPreference = "Stop"
$ua = "Mozilla/5.0"

if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_SECRET_KEY) {
  throw "Faltam os secrets SUPABASE_URL / SUPABASE_SECRET_KEY"
}
$base = $env:SUPABASE_URL.TrimEnd("/")
$key  = $env:SUPABASE_SECRET_KEY

function New-Header([hashtable]$extra = @{}) {
  $h = @{ apikey = $key }
  if ($key.StartsWith("eyJ")) { $h["Authorization"] = "Bearer $key" }
  foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] }
  return $h
}

# 1) Todos os ea_id da tabela cartas (a API devolve no maximo 1000 por pedido)
$ids = New-Object System.Collections.Generic.List[int64]
$off = 0
do {
  $pag = Invoke-RestMethod "$base/rest/v1/cartas?select=ea_id&order=ea_id.asc&limit=1000&offset=$off" -Headers (New-Header)
  foreach ($c in $pag) { $ids.Add([int64]$c.ea_id) }
  $off += 1000
} while (@($pag).Count -eq 1000)
if ($ids.Count -eq 0) { throw "Tabela cartas vazia - corre primeiro o sync-cartas" }
"Cartas na base: $($ids.Count)"

# 2) Quantas cartas ja tinham preco antes (para a salvaguarda)
$r = Invoke-WebRequest "$base/rest/v1/precos?select=ea_id&preco_consola=gt.0&limit=1" -Headers (New-Header @{ Prefer = "count=exact" })
$antes = [int](([string]@($r.Headers["Content-Range"])[0] -split "/")[1])

# 3) Ler precos no FUT Mind, em lotes de 100
function Ler-Lote([int64[]]$lote) {
  $u = "https://futmind.com/api/beta/players/prices?resourceIds=" + [uri]::EscapeDataString($lote -join ",")
  for ($t = 1; $t -le 2; $t++) {
    try { return Invoke-RestMethod $u -UserAgent $ua }
    catch {
      if ($t -eq 2) { throw }
      Write-Warning "Lote falhou ($($_.Exception.Message)), a tentar de novo em 5s"
      Start-Sleep -Seconds 5
    }
  }
}

$agora = (Get-Date).ToUniversalTime().ToString("o")
$rows  = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $ids.Count; $i += 100) {
  $lote = $ids.GetRange($i, [Math]::Min(100, $ids.Count - $i)).ToArray()
  $resp = Ler-Lote $lote
  foreach ($p in $resp.PSObject.Properties) {
    $rows.Add([ordered]@{
      ea_id         = [int64]$p.Name
      preco_consola = [int]$p.Value.consolePrice
      preco_pc      = [int]$p.Value.pcPrice
      atualizado_em = $agora
    })
  }
  Start-Sleep -Milliseconds 1500
}

# 4) Salvaguardas
$comPreco = @($rows | Where-Object { $_.preco_consola -gt 0 }).Count
"Pedidas: $($ids.Count) | devolvidas: $($rows.Count) | com preco (consola): $comPreco | a zero: $($rows.Count - $comPreco) | com preco antes na base: $antes"
foreach ($amostra in 273153, 50534459) {
  $a = $rows | Where-Object { $_.ea_id -eq $amostra }
  if ($a) { "amostra $amostra : consola=$($a.preco_consola) pc=$($a.preco_pc)" }
}
if ($rows.Count -lt 0.95 * $ids.Count) { throw "Voltaram so $($rows.Count) de $($ids.Count) cartas - nao gravo" }
if ($comPreco -eq 0)                    { throw "Nenhum preco veio acima de zero - nao gravo" }
if ($antes -gt 0 -and $comPreco -lt 0.7 * $antes) { throw "Cartas com preco caiu de $antes para $comPreco - nao gravo" }

# 5) Gravar
for ($i = 0; $i -lt $rows.Count; $i += 500) {
  $fim  = [Math]::Min($i + 499, $rows.Count - 1)
  $json = $rows.GetRange($i, $fim - $i + 1) | ConvertTo-Json -Depth 4 -AsArray
  Invoke-RestMethod -Method Post -Uri "$base/rest/v1/precos?on_conflict=ea_id" `
    -Headers (New-Header @{ Prefer = "resolution=merge-duplicates,return=minimal" }) `
    -ContentType "application/json; charset=utf-8" -Body $json | Out-Null
}
"Gravados: $($rows.Count) precos"
